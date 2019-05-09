require 'faraday'
require 'nokogiri'
require 'pry'
require 'webmock'
require 'vcr'
require 'slack-notifier'
require 'dotenv/load'
require 'holiday_jp'
require 'nkf'

exit if HolidayJp.holiday?(Date.today)

def main
    response = nil
    attachments = []

    connection = Faraday::Connection.new do |builder|
        builder.use Faraday::Request::UrlEncoded
        builder.use Faraday::Response::Logger if $DEBUG
        builder.use Faraday::Adapter::NetHttp
    end

    # contentType:"application/json; charset=utf-8",
    connection.basic_auth(ENV['ATLASSIAN_LOGIN'], ENV['ATLASSIAN_PASS'])
    response = connection.get('https://fukurou-labo.atlassian.net/wiki/rest/api/content/65208323?expand=body.storage') do |req|
        req.headers['Content-Type'] = 'application/json; charset=utf-8'
    end

    body = response.body.force_encoding('UTF-8').gsub(/\\u[0-9A-H]{4}\\u[0-9A-H]{4}/) {|m| str = m[2..5] + m[8..11]; NKF.nkf('-W16 -w', str.scan(/../).map(&:hex).map(&:chr).join) }
    html = Nokogiri::HTML.parse(body, nil, 'UTF-8')
    layout_cell = html.css('layout-cell').first

    before_h4 = nil
    layout_cell.children.each do |tag|
        case tag.name
        when 'h4'
            before_h4 = tag
        when 'ul'
            before_h4.inner_text
            inner_text_list = tag.children.map {|r| r.inner_text }
            attachments << { text: inner_text_list.map {|r| "・#{r}" }.join("\n"),
                             pretext: before_h4.inner_text,
                             color: '#b0c4de' }
        else
        end
    end

    notifier = Slack::Notifier.new(ENV['CX_SLACK_WEBHOOK_URL'],
                                   channel: ENV['NOTIFY_CHANNEL'],
                                   icon_emoji: ':fukurouchan:',
                                   link_names: true,
                                   username: 'Dev作業進捗フクロウ')
    notifier.ping('', attachments: attachments)
    notifier = Slack::Notifier.new(ENV['CX_SLACK_WEBHOOK_URL'],
                                   channel: ENV['NOTIFY_CHANNEL'],
                                   icon_emoji: ':fukurouchan:',
                                   link_names: true,
                                   username: 'Dev作業進捗フクロウ')
    notifier.ping(<<-EOS)
    ```
詳細は以下を参照して下さい
https://fukurou-labo.atlassian.net/wiki/spaces/DEV/pages/65208323/DEV
    ````
    EOS
end

begin
    main
rescue => ex
    puts ex.message
end