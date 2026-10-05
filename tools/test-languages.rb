# frozen_string_literal: true

require 'json'
require 'nokogiri'
require 'pathname'

root = Pathname.new(ARGV.fetch(0, '_site'))
def check(condition, message)
  raise message unless condition
end

check(root.join('index.html').read.include?('url=/jp/'), 'Root must redirect to Japanese')
locales = { 'jp' => 'ja-JP', 'en' => 'en', 'ko' => 'ko-KR' }
locales.each do |language, locale|
  others = locales.keys - [language]
  dir = root.join(language)
  search = JSON.parse(dir.join('assets/js/data/search.json').read)
  check(!search.empty?, "#{language}: search index is empty")
  search.each do |post|
    check(post['url'].start_with?("/#{language}/"), "#{language}: foreign search result")
    check(root.join(post['url'].delete_prefix('/'), 'index.html').file?, "Missing post: #{post['url']}")
  end
  foreign_titles = others.flat_map { |other| JSON.parse(root.join(other, 'assets/js/data/search.json').read).map { |post| post['title'] } }
  foreign_titles -= search.map { |post| post['title'] }
  Dir[dir.join('**/*.html')].each do |file|
    html = Nokogiri::HTML(File.read(file))
    check(html.at_css('html')['lang'] == locale, "Wrong UI language: #{file}")
    html.css('a[href]').each do |link|
      href = link['href']
      next if link['hreflang'] # The explicit language switch is the only cross-language navigation.
      check(others.none? { |other| href.start_with?("/#{other}/") }, "Foreign link in #{file}: #{href}")
      check(!foreign_titles.include?(link.text.strip), "Foreign post title in #{file}")
    end
    if html.at_css('#post-list')
      check(!html.css('#post-list .post-preview').empty?, "Empty home/pagination page: #{file}")
    end
  end
  %w[categories tags archives about].each do |tab|
    check(dir.join(tab, 'index.html').file?, "Missing #{language}/#{tab}")
  end
  check(dir.join('intro-vpn/index.html').file?, "Existing #{language} post URL changed")
end
puts 'Language isolation, UI locales, navigation, search and existing URLs passed.'
