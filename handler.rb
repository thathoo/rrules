require 'base64'
require 'cgi'
require 'json'
require 'time'
require 'rrule'

DEFAULT_TIME_ZONE = 'UTC'
DEFAULT_END_TIME_SECONDS = 365 * 24 * 60 * 60
# Approximate range guard to keep recurrence expansion bounded.
BOUNDARY_SECONDS = (100 * 365.25 * 24 * 60 * 60).to_i

class InvalidJsonBody < StandardError; end

def rrule_expand(event:, context:)
  params = request_params(event || {})

  missing = %w[rrule start_time].select { |key| blank?(params[key]) }
  return json_response(400, error: 'missing_parameter', message: "Missing required parameter(s): #{missing.join(', ')}") if missing.any?

  now = Time.now.utc
  start_time = parse_time(params['start_time'], 'start_time')
  end_time = blank?(params['end_time']) ? now + DEFAULT_END_TIME_SECONDS : parse_time(params['end_time'], 'end_time')
  time_zone = blank?(params['time_zone']) ? DEFAULT_TIME_ZONE : params['time_zone']

  if end_time < start_time
    return json_response(422, error: 'invalid_time_range', message: 'end_time must be after start_time')
  end

  if start_time < now - BOUNDARY_SECONDS || end_time > now + BOUNDARY_SECONDS
    return json_response(
      422,
      error: 'outside_supported_range',
      message: 'start_time or end_time cannot be outside the supported 100 year boundary'
    )
  end

  rule = RRule::Rule.new(params['rrule'], tzid: time_zone, dtstart: start_time)
  occurrences = rule.between(start_time, end_time).map { |time| time.utc.iso8601 }

  json_response(200, message: 'ok', occurrences: occurrences)
rescue JSON::ParserError
  json_response(400, error: 'invalid_json', message: 'Request body must be valid JSON')
rescue InvalidJsonBody => e
  json_response(400, error: 'invalid_json', message: e.message)
rescue RRule::InvalidRRule => e
  json_response(400, error: 'invalid_rrule', message: e.message)
rescue ArgumentError => e
  json_response(400, error: 'invalid_parameter', message: e.message)
rescue StandardError => e
  warn "#{e.class}: #{e.message}"
  json_response(500, error: 'internal_error', message: 'Unexpected error while expanding RRULE')
end

def request_params(event)
  query_params = normalize_hash(event['queryStringParameters'] || event[:queryStringParameters] || {})
  body_params = parse_body(event)

  query_params.merge(body_params)
end

def parse_body(event)
  body = event['body'] || event[:body]
  return {} if blank?(body)

  body = Base64.decode64(body) if event['isBase64Encoded'] || event[:isBase64Encoded]
  body = body.to_s.strip
  return {} if body.empty?

  if json_request?(event) || body.start_with?('{', '[')
    parsed = JSON.parse(body)
    return normalize_hash(parsed) if parsed.is_a?(Hash)

    raise InvalidJsonBody, 'JSON request body must be an object'
  end

  CGI.parse(body).transform_values(&:first)
end

def json_request?(event)
  headers = normalize_hash(event['headers'] || event[:headers] || {})
  content_type = headers['content-type'] || headers['Content-Type']

  content_type.to_s.downcase.include?('application/json')
end

def normalize_hash(hash)
  hash.each_with_object({}) do |(key, value), normalized|
    normalized[key.to_s] = value
  end
end

def parse_time(value, field)
  Time.parse(value.to_s)
rescue ArgumentError
  raise ArgumentError, "#{field} must be a parseable time"
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def json_response(status_code, payload)
  {
    statusCode: status_code,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*'
    },
    body: JSON.generate(payload)
  }
end
