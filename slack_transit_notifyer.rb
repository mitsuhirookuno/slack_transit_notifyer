require 'google_drive'
require 'pry'
require 'date'
require 'faraday'
require 'nokogiri'
require 'webmock'
require 'vcr'
require 'slack-notifier'
require 'dotenv/load'
require 'holiday_jp'

exit if HolidayJp.holiday?(Date.today)

SCHEDULED = ARGV[0]

class Notification
  attr_accessor :name, :scheduled_at, :route, :holidays

  def initialize(name: , scheduled_at: , route: , holidays: )
    @name = name
    @scheduled_at = scheduled_at
    @route = route
    @holidays = [nil] + holidays  # 日 月 火 水 木 金 土
  end

  def holiday?
    @scheduled_at[Date.today.wday] == 'TRUE'
  end

  def valid?
    return false if @name.size.zero?
    return false if holiday?
    return false if @scheduled_at != SCHEDULED
    true
  end

  def self.build_notification(notification_row)
    Notification.new(name: notification_row[1], scheduled_at: notification_row[2], route: notification_row[3], holidays: notification_row[4..8])
  end
end

def get_traininfo
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

  html = Nokogiri::HTML.parse(response.body, nil, 'utf-8')
  troubles = html.css('.elmTblLstLine.trouble')
  troubles.css('tr').each_with_object({}) do |tr, h|
    next unless tr.css('th').size.zero?
    h[tr.css('a').inner_html] = {status: tr.css('.colTrouble').inner_html, detail: tr.css('td:last-child').inner_html }
  end
end

def main
  # config.jsonを読み込んでセッションを確立
  session = GoogleDrive::Session.from_config("config.json")

  # スプレッドシートをURLで取得
  spreadsheet = session.spreadsheet_by_url(ENV['SPREADSHEET_URL'])
  notification_rows = spreadsheet.worksheet_by_title("通知設定").rows
  member_rows = spreadsheet.worksheet_by_title("設定（メンバー）").rows
  route_rows = spreadsheet.worksheet_by_title("設定（路線）").rows
  time_rows = spreadsheet.worksheet_by_title("設定（時刻）").rows

  notifications = notification_rows[1..].map { |r| Notification.build_notification(r) }.select(&:valid?)

  train_info = get_traininfo
  route_by_notifications = notifications.group_by(&:route).select! {|k,v| train_info.keys.include?(k) }

  attachments = []

  train_info.select {|k, v| route_by_notifications.keys.include?(k) }.each do |train, info|
    member_ids = route_by_notifications[train].map(&:name).map { |name| member_rows.to_h[name] }
    attachments << {title: ":train: #{info[:status]}",
                    text: info[:detail],
                    pretext: "#{train} <@#{member_ids.join('> <@')}>",
                    color: '#ff7f50'}
  end

  return if attachments.size.zero?
  notifier = Slack::Notifier.new(ENV['SLACK_WEBHOOK_URL'],
                                 channel: ENV['NOTIFY_CHANNEL'],
                                 link_names: true,
                                 username: 'baymax')
  notifier.ping(':warning: 以下の路線に遅延が発生しています :warning: ', attachments: attachments)
end

main
