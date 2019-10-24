require 'faraday'
require 'nokogiri'
require 'pry'
require 'webmock'
require 'vcr'
require 'slack-notifier'
require 'dotenv/load'
require 'holiday_jp'

exit if HolidayJp.holiday?(Date.today)

VCR.configure do |c|
  c.cassette_library_dir = 'tmp/cache/vcr'
  c.hook_into :webmock
  c.allow_http_connections_when_no_cassette = true
end

SETTING = YAML.load(open('setting.yaml').read)

def main
  response = nil
  connection = Faraday::Connection.new do |builder|
    builder.use Faraday::Request::UrlEncoded
    builder.use Faraday::Response::Logger if $DEBUG
    builder.use Faraday::Adapter::NetHttp
  end

  if $DEBUG
    VCR.use_cassette 'tenki.jp/indexes/umbrella/3/16/4410/' do
      response = connection.get('https://tenki.jp/indexes/umbrella/3/16/4410/')
    end
  else
    response = connection.get('https://tenki.jp/indexes/umbrella/3/16/4410/')
  end

  html = Nokogiri::HTML.parse(response.body, nil, 'utf-8')
  max_temperature, min_temperature = html.css('section.today-weather > div > div > div.weather-icon-box > p.indexes-weather-date-value').inner_text.scan(/\d+℃/)
  rainfall_rate = html.css('section.today-weather > div > div > div.indexes-icon-box > span').inner_text.to_i
  description = html.css('section.today-weather > div > p').inner_text
  notifier = Slack::Notifier.new(ENV['SLACK_WEBHOOK_URL'],
                                 channel: ENV['NOTIFY_CHANNEL'],
                                 link_names: true,
                                 username: 'baymax')
  notifier.ping(":thermometer: #{max_temperature}〜#{min_temperature} :thermometer:")
  exit if rainfall_rate < 40
  notifier.ping(":umbrella: #{description} :umbrella:")
end

begin
  main
rescue => ex
  puts ex.message
end
