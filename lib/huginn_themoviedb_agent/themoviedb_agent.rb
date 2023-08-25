module Agents
  class ThemoviedbAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The moviedb Agent interacts with Themoviedb API.

      `debug` is used for verbose mode.

      `token` is used for authentication.

      `type` is for the wanted action like tv_show_details.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "id": 3718988,
            "name": "Jibaro",
            "overview": "A deaf knight and a siren of myth become entwined in a deadly dance. A fatal attraction infused with blood, death and treasure.",
            "vote_average": 8.123,
            "vote_count": 65,
            "air_date": "2022-05-21",
            "episode_number": 9,
            "episode_type": "finale",
            "production_code": "",
            "runtime": 18,
            "season_number": 3,
            "show_id": 86831,
            "still_path": "/qWHGEsBFoh0Cq3AEWoMsxLZOayx.jpg",
            "original_name": "Love, Death & Robots",
            "event_type": "last episode"
          }
    MD

    def default_options
      {
        'type' => 'tv_show_details',
        'token' => '',
        'series_id' => '',
        'debug' => 'false',
        'emit_events' => 'true',
        'expected_receive_period_in_days' => '2',
      }
    end

    form_configurable :token, type: :string
    form_configurable :series_id, type: :string
    form_configurable :debug, type: :boolean
    form_configurable :emit_events, type: :boolean
    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :type, type: :array, values: ['tv_show_details']
    def validate_options
      errors.add(:base, "type has invalid value: should be 'tv_show_details'") if interpolated['type'].present? && !%w(tv_show_details).include?(interpolated['type'])

      unless options['token'].present? || !['tv_show_details'].include?(options['type'])
        errors.add(:base, "token is a required field")
      end

      unless options['series_id'].present? || !['tv_show_details'].include?(options['type'])
        errors.add(:base, "series_id is a required field")
      end

      if options.has_key?('emit_events') && boolify(options['emit_events']).nil?
        errors.add(:base, "if provided, emit_events must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          log event
          trigger_action
        end
      end
    end

    def check
      trigger_action
    end

    private

    def log_curl_output(code,body)

      log "request status : #{code}"

      if interpolated['debug'] == 'true'
        log "body"
        log body
      end

    end

    def season_details(original_name,season_number)
      log original_name
      log season_number

      url = URI("https://api.themoviedb.org/3/tv/#{interpolated['series_id']}/season/#{season_number}?language=en-US")

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(url)
      request["accept"] = 'application/json'
      request["Authorization"] = "Bearer #{interpolated['token']}"

      response = http.request(request)

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)

      payload['episodes'].each do |episode|
        if interpolated['emit_events'] == 'true'
          event_created = episode.dup
          event_created['original_name'] = original_name
          event_created['event_type'] = 'new episode'
          create_event payload: event_created
        end
      end

    end

    def tv_show_details()

      url = URI("https://api.themoviedb.org/3/tv/#{interpolated['series_id']}?language=en-US")
      
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      
      request = Net::HTTP::Get.new(url)
      request["accept"] = 'application/json'
      request["Authorization"] = "Bearer #{interpolated['token']}"

      response = http.request(request)

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)

      if payload.to_s != memory['last_status']
        if "#{memory['last_status']}" == ''
          create_event payload: payload
        else
          last_status = memory['last_status']
          if payload['last_air_date'] != last_status['last_air_date']
            event_created = payload['last_episode_to_air'].dup
            event_created['original_name'] = payload['original_name']
            event_created['event_type'] = 'last episode'
            create_event payload: event_created
          end
          payload['seasons'].each do | season |
            found = false
            last_status['seasons'].each do | seasonbis |
              if season == seasonbis || season['id'] == seasonbis['id']
                found = true
              end
            end
            if interpolated['debug'] == 'true'
              log found
            end
            if found == false
              event_created = season.dup
              event_created['original_name'] = payload['original_name']
              event_created['event_type'] = 'new season'
              create_event :payload => event_created
              season_details(payload['original_name'],payload['number_of_seasons'])
            end
          end
        end
        memory['last_status'] = payload
      end

    end

    def trigger_action

      case interpolated['type']
      when "tv_show_details"
        tv_show_details()
      else
        log "Error: type has an invalid value (#{interpolated['type']})"
      end
    end
  end
end
