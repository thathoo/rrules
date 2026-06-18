require 'base64'
require 'json'
require 'uri'

require_relative '../handler'

RSpec.describe '#router' do
  def routed_response_for(event)
    response = router(event: event, context: nil)
    response.merge(body: JSON.parse(response[:body]))
  end

  it 'routes health checks' do
    response = routed_response_for(
      'requestContext' => { 'http' => { 'method' => 'GET' } },
      'rawPath' => '/health'
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]).to eq('message' => 'ok')
  end

  it 'routes RRULE expansion requests' do
    response = routed_response_for(
      'routeKey' => 'POST /rrule_expand',
      'requestContext' => { 'http' => { 'method' => 'POST' }, 'stage' => 'prod' },
      'rawPath' => '/rrule_expand',
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=1',
        'start_time' => '2019-03-05 00:46:42 -0800'
      )
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]['occurrences']).to eq(['2019-03-05T08:46:42Z'])
  end

  it 'routes named-stage HTTP API events using routeKey' do
    response = routed_response_for(
      'routeKey' => 'POST /rrule_expand',
      'requestContext' => { 'http' => { 'method' => 'POST' }, 'stage' => 'prod' },
      'rawPath' => '/prod/rrule_expand',
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=1',
        'start_time' => '2019-03-05 00:46:42 -0800'
      )
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]['occurrences']).to eq(['2019-03-05T08:46:42Z'])
  end

  it 'strips named-stage prefixes when falling back to path routing' do
    response = routed_response_for(
      'requestContext' => { 'http' => { 'method' => 'GET' }, 'stage' => 'prod' },
      'rawPath' => '/prod/health'
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]).to eq('message' => 'ok')
  end

  it 'returns not found for unknown routes' do
    response = routed_response_for(
      'requestContext' => { 'http' => { 'method' => 'GET' } },
      'rawPath' => '/missing'
    )

    expect(response[:statusCode]).to eq(404)
    expect(response[:body]).to eq(
      'error' => 'not_found',
      'message' => 'Route not found'
    )
  end

  it 'does not return app-level CORS headers' do
    response = router(
      event: {
        'routeKey' => 'GET /health',
        'requestContext' => { 'http' => { 'method' => 'GET' } },
        'rawPath' => '/health'
      },
      context: nil
    )

    expect(response[:headers]).to eq('Content-Type' => 'application/json')
  end
end

RSpec.describe '#rrule_expand' do
  def response_for(event)
    response = rrule_expand(event: event, context: nil)
    response.merge(body: JSON.parse(response[:body]))
  end

  it 'expands RRULEs from a JSON request body' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=3',
        'start_time' => '2019-03-05 00:46:42 -0800',
        'end_time' => '2019-06-05 00:46:42 -0800'
      )
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]).to eq(
      'message' => 'ok',
      'occurrences' => [
        '2019-03-05T08:46:42Z',
        '2019-03-06T08:46:42Z',
        '2019-03-07T08:46:42Z'
      ]
    )
  end

  it 'expands RRULEs from a form-encoded request body' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/x-www-form-urlencoded' },
      'body' => URI.encode_www_form(
        'rrule' => 'FREQ=DAILY;COUNT=2',
        'start_time' => '2019-03-05 00:46:42 -0800',
        'end_time' => '2019-03-07 00:46:42 -0800'
      )
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]['occurrences']).to eq([
      '2019-03-05T08:46:42Z',
      '2019-03-06T08:46:42Z'
    ])
  end

  it 'defaults end_time for JSON request bodies' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=3',
        'start_time' => '2019-03-05 00:46:42 -0800'
      )
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]['occurrences'].size).to eq(3)
  end

  it 'reads query string parameters' do
    response = response_for(
      'queryStringParameters' => {
        'rrule' => 'FREQ=WEEKLY;COUNT=2',
        'start_time' => '2019-03-05 00:46:42 -0800',
        'end_time' => '2019-04-05 00:46:42 -0800'
      }
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]['occurrences']).to eq([
      '2019-03-05T08:46:42Z',
      '2019-03-12T08:46:42Z'
    ])
  end

  it 'expands RRULEs from base64-encoded JSON request bodies' do
    body = JSON.generate(
      'rrule' => 'FREQ=DAILY;COUNT=2',
      'start_time' => '2019-03-05 00:46:42 -0800',
      'end_time' => '2019-03-07 00:46:42 -0800'
    )

    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'isBase64Encoded' => true,
      'body' => Base64.strict_encode64(body)
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]['occurrences']).to eq([
      '2019-03-05T08:46:42Z',
      '2019-03-06T08:46:42Z'
    ])
  end

  it 'uses body parameters when both body and query string parameters are present' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'queryStringParameters' => {
        'rrule' => 'FREQ=WEEKLY;COUNT=1',
        'start_time' => '2020-01-01 00:00:00 -0800',
        'end_time' => '2020-01-10 00:00:00 -0800'
      },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=2',
        'start_time' => '2019-03-05 00:46:42 -0800',
        'end_time' => '2019-03-07 00:46:42 -0800'
      )
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]['occurrences']).to eq([
      '2019-03-05T08:46:42Z',
      '2019-03-06T08:46:42Z'
    ])
  end

  it 'applies the requested time zone when expanding occurrences' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=2',
        'start_time' => '2019-03-05 00:46:42',
        'end_time' => '2019-03-07 00:46:42',
        'time_zone' => 'America/Los_Angeles'
      )
    )

    expect(response[:statusCode]).to eq(200)
    expect(response[:body]['occurrences']).to eq([
      '2019-03-05T08:46:42Z',
      '2019-03-06T08:46:42Z'
    ])
  end

  it 'returns structured errors for invalid JSON' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => '{"rrule":'
    )

    expect(response[:statusCode]).to eq(400)
    expect(response[:body]).to eq(
      'error' => 'invalid_json',
      'message' => 'Request body must be valid JSON'
    )
  end

  it 'returns structured errors when JSON request bodies are not objects' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(['FREQ=DAILY;COUNT=3'])
    )

    expect(response[:statusCode]).to eq(400)
    expect(response[:body]).to eq(
      'error' => 'invalid_json',
      'message' => 'JSON request body must be an object'
    )
  end

  it 'returns structured errors for missing required parameters' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate('start_time' => '2019-03-05 00:46:42 -0800')
    )

    expect(response[:statusCode]).to eq(400)
    expect(response[:body]).to eq(
      'error' => 'missing_parameter',
      'message' => 'Missing required parameter(s): rrule'
    )
  end

  it 'returns structured errors for invalid times' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=3',
        'start_time' => 'not a time'
      )
    )

    expect(response[:statusCode]).to eq(400)
    expect(response[:body]).to eq(
      'error' => 'invalid_parameter',
      'message' => 'start_time must be a parseable time'
    )
  end

  it 'returns structured errors for invalid RRULEs' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=NOPE',
        'start_time' => '2019-03-05 00:46:42 -0800'
      )
    )

    expect(response[:statusCode]).to eq(400)
    expect(response[:body]).to eq(
      'error' => 'invalid_rrule',
      'message' => 'Valid FREQ value is required'
    )
  end

  it 'returns structured errors for invalid time zones' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=1',
        'start_time' => '2019-03-05 00:46:42 -0800',
        'time_zone' => 'Mars/Olympus'
      )
    )

    expect(response[:statusCode]).to eq(400)
    expect(response[:body]).to eq(
      'error' => 'invalid_parameter',
      'message' => 'Invalid Timezone: Mars/Olympus'
    )
  end

  it 'returns structured errors when end_time is before start_time' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=1',
        'start_time' => '2019-03-05 00:46:42 -0800',
        'end_time' => '2019-03-04 00:46:42 -0800'
      )
    )

    expect(response[:statusCode]).to eq(422)
    expect(response[:body]).to eq(
      'error' => 'invalid_time_range',
      'message' => 'end_time must be after start_time'
    )
  end

  it 'returns structured errors for requests outside the supported 100 year boundary' do
    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=YEARLY;COUNT=1',
        'start_time' => Time.now.utc.iso8601,
        'end_time' => (Time.now.utc + BOUNDARY_SECONDS + 86_400).iso8601
      )
    )

    expect(response[:statusCode]).to eq(422)
    expect(response[:body]).to eq(
      'error' => 'outside_supported_range',
      'message' => 'start_time or end_time cannot be outside the supported 100 year boundary'
    )
  end

  it 'returns structured errors when expansion exceeds the occurrence limit' do
    stub_const('MAX_OCCURRENCES', 2)

    response = response_for(
      'headers' => { 'Content-Type' => 'application/json' },
      'body' => JSON.generate(
        'rrule' => 'FREQ=DAILY;COUNT=3',
        'start_time' => '2019-03-05 00:46:42 -0800',
        'end_time' => '2019-03-10 00:46:42 -0800'
      )
    )

    expect(response[:statusCode]).to eq(422)
    expect(response[:body]).to eq(
      'error' => 'too_many_occurrences',
      'message' => 'RRULE expansion is limited to 2 occurrences'
    )
  end
end
