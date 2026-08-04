#!/usr/bin/env ruby

require "json"
require "nokogiri"
require "pathname"
require "uri"

site_root = Pathname.new(ARGV.fetch(0, "_site")).expand_path
errors = []
documents = {}

Dir[site_root.join("**/*.html")].sort.each do |filename|
  path = Pathname.new(filename)
  document = Nokogiri::HTML5(File.read(path))
  route = "/#{path.relative_path_from(site_root)}".sub(%r{/index\.html$}, "/")
  documents[route] = document

  errors << "#{route}: expected one main landmark" unless document.css("main").length == 1
  errors << "#{route}: expected one h1" unless document.css("h1").length == 1
  errors << "#{route}: missing meta description" if document.at_css('meta[name="description"]')&.[]("content").to_s.strip.empty?
  errors << "#{route}: missing canonical URL" if document.at_css('link[rel="canonical"]')&.[]("href").to_s.strip.empty?
  errors << "#{route}: missing Open Graph title" if document.at_css('meta[property="og:title"]')&.[]("content").to_s.strip.empty?

  ids = document.css("[id]").map { |node| node["id"] }
  duplicates = ids.tally.select { |_id, count| count > 1 }.keys
  errors << "#{route}: duplicate IDs #{duplicates.join(', ')}" unless duplicates.empty?

  document.css("img").each do |image|
    errors << "#{route}: image missing alt text" unless image.key?("alt") && !image["alt"].strip.empty?
  end

  document.css('script[type="application/ld+json"]').each do |script|
    JSON.parse(script.text)
  rescue JSON::ParserError => error
    errors << "#{route}: invalid JSON-LD (#{error.message})"
  end

  errors << "#{route}: public phone link found" if document.at_css('a[href^="tel:"]')
end

def output_path_for(site_root, raw_path)
  clean_path = raw_path.sub(%r{^/}, "")
  candidate = site_root.join(clean_path)
  return candidate if candidate.file?
  return candidate.join("index.html") if candidate.directory?
  return site_root.join(clean_path, "index.html") unless File.extname(clean_path).length.positive?
  candidate
end

documents.each do |route, document|
  document.css("a[href]").each do |link|
    href = link["href"].to_s
    next if href.empty? || href.start_with?("mailto:", "http://", "https://")

    path_part, fragment = href.split("#", 2)
    target_route = if path_part.empty?
      route
    elsif path_part.start_with?("/")
      path_part
    else
      File.expand_path(path_part, File.dirname(route)).sub(%r{\A/}, "/")
    end

    target_file = output_path_for(site_root, target_route)
    unless target_file.file?
      errors << "#{route}: broken internal link #{href}"
      next
    end

    next if fragment.nil? || fragment.empty?
    target_document = Nokogiri::HTML5(File.read(target_file))
    errors << "#{route}: missing anchor target #{href}" unless target_document.at_css("##{fragment}")
  end
end

%w[index.html academic/index.html 404.html robots.txt sitemap.xml].each do |required|
  errors << "Missing generated file: #{required}" unless site_root.join(required).file?
end

if errors.empty?
  puts "Site validation passed: #{documents.length} HTML pages checked."
else
  warn errors.join("\n")
  exit 1
end
