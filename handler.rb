require 'base64'
require 'cgi'
require 'date'
require 'json'
require 'time'
require 'tzinfo'
require 'rrule'

DEFAULT_TIME_ZONE = 'UTC'
DEFAULT_END_TIME_SECONDS = 365 * 24 * 60 * 60
# Approximate range guard to keep recurrence expansion bounded.
BOUNDARY_SECONDS = (100 * 365.25 * 24 * 60 * 60).to_i

class InvalidJsonBody < StandardError; end

def router(event:, context:)
  method = request_method(event || {})
  path = request_path(event || {})

  return json_response(204, {}) if method == 'OPTIONS'
  return health_check(event: event, context: context) if method == 'GET' && path == '/health'
  return rrule_expand(event: event, context: context) if method == 'POST' && path == '/rrule_expand'

  json_response(404, error: 'not_found', message: 'Route not found')
end

def health_check(event:, context:)
  json_response(200, message: 'ok')
end

def rrule_expand(event:, context:)
  params = request_params(event || {})

  missing = %w[rrule start_time].select { |key| blank?(params[key]) }
  return json_response(400, error: 'missing_parameter', message: "Missing required parameter(s): #{missing.join(', ')}") if missing.any?

  now = Time.now.utc
  time_zone = blank?(params['time_zone']) ? DEFAULT_TIME_ZONE : params['time_zone']
  start_time = parse_time(params['start_time'], 'start_time', time_zone)
  end_time = blank?(params['end_time']) ? now + DEFAULT_END_TIME_SECONDS : parse_time(params['end_time'], 'end_time', time_zone)

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

def request_method(event)
  event.dig('requestContext', 'http', 'method') ||
    event.dig(:requestContext, :http, :method) ||
    event['httpMethod'] ||
    event[:httpMethod]
end

def request_path(event)
  event['rawPath'] ||
    event[:rawPath] ||
    event['path'] ||
    event[:path]
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

def parse_time(value, field, time_zone = nil)
  string = value.to_s
  return Time.parse(string) if time_zone.nil? || explicit_time_zone?(string)

  parsed = Date._parse(string)
  return Time.parse(string) unless parsed.values_at(:year, :mon, :mday).all?

  TZInfo::Timezone.get(time_zone).local_time(
    parsed[:year],
    parsed[:mon],
    parsed[:mday],
    parsed.fetch(:hour, 0),
    parsed.fetch(:min, 0),
    parsed.fetch(:sec, 0)
  ).to_time
rescue TZInfo::InvalidTimezoneIdentifier
  raise ArgumentError, "Invalid Timezone: #{time_zone}"
rescue ArgumentError, TypeError
  raise ArgumentError, "#{field} must be a parseable time"
end

def explicit_time_zone?(value)
  value.match?(/(?:Z|[+-]\d{2}:?\d{2}|\b[A-Z]{2,4})\z/)
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def json_response(status_code, payload)
  {
    statusCode: status_code,
    headers: {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Headers' => 'content-type',
      'Access-Control-Allow-Methods' => 'GET,POST,OPTIONS'
    },
    body: JSON.generate(payload)
  }
end
