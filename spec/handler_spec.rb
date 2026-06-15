require 'json'
require 'uri'

require_relative '../handler'

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
end
