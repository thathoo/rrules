require 'json'
require 'time'
require 'rrule'

def rrule_expand(event:, context:)
  begin
    if event['body'].present?
      body = JSON.parse(event['body'])
      rrule = body['rrule']
      start_time = body['start_time']
      end_time = body['end_time']
      time_zone = body['time_zone'] || 'UTC'
    else
      rrule = event['queryStringParameters']['rrule']
      start_time = event['queryStringParameters']['start_time']
      end_time = event['queryStringParameters'].try(:[], 'end_time') || 1.year.from_now.to_s
      time_zone = event['queryStringParameters'].try(:[], 'time_zone') || 'UTC'
    end
    puts "rrule: #{rrule}, start_time: #{start_time}, end_time: #{end_time}, time_zone: #{time_zone}"

    parsed_start_time = Time.parse(start_time)
    parsed_end_time = Time.parse(end_time)

    if (parsed_start_time < 100.years.ago) || (parsed_end_time > 100.years.from_now)
      message = "start_time or end_time cannot be outside 100 years boundary"
      { statusCode: 200, body: JSON.generate({ message: message, rrules: [] }) }
    else
      rrule = RRule::Rule.new(rrule, tzid: time_zone, dtstart: Time.parse(start_time))
      rrules = rrule.between(Time.parse(start_time), Time.parse(end_time))

      message = "No failure detected"
      { statusCode: 200, body: JSON.generate({ message: message, rrules: rrules.join(', ') }) }
    end
  rescue StandardError => e  
    { statusCode: 400, body: JSON.generate("exception: #{e.backtrace}") }
  end
end
