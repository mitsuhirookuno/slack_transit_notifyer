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
  attachments = []
  routes = Hash.new {|hash, key| hash[key] = []}
  routes = SETTING['Members'].each_with_object(routes) {|m, h| m['Routes'].each {|r| h[r] << m['UserId']}}

  connection = Faraday::Connection.new do |builder|
    builder.use Faraday::Request::UrlEncoded
    builder.use Faraday::Response::Logger if $DEBUG
    builder.use Faraday::Adapter::NetHttp
  end

  if $DEBUG
    VCR.use_cassette 'transit.yahoo.co.jp/traininfo/area/4' do
      response = connection.get('https://transit.yahoo.co.jp/traininfo/area/4/')
    end
  else
    response = connection.get('https://transit.yahoo.co.jp/traininfo/area/4/')
  end

  # TODO : response.headers['content-type']
  html = Nokogiri::HTML.parse(response.body, nil, 'utf-8')
  troubles = html.css('.elmTblLstLine.trouble')
  troubles.css('tr').each do |tr|
    next unless tr.css('th').size.zero?
    next unless routes.keys.include?(tr.css('a').inner_html)

    names = routes[tr.css('a').inner_html]
    attachments << {title: ":train: #{tr.css('.colTrouble').inner_html}",
                    text: tr.css('td:last-child').inner_html,
                    pretext: "#{tr.css('a').inner_html} <@#{names.join('> <@')}>",
                    color: '#ff7f50'}
  end
  return if attachments.size.zero?
  notifier = Slack::Notifier.new(ENV['CX_SLACK_WEBHOOK_URL'],
                                 channel: ENV['NOTIFY_CHANNEL'],
                                 icon_emoji: ':fukurouchan:',
                                 link_names: true,
                                 username: '交通情報梟')
  notifier.ping(':warning: 以下の路線に遅延が発生しています :warning: ', attachments: attachments)
end

begin
  main
rescue => ex
  puts ex.message
end