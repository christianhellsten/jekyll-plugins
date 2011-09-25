require 'open-uri'
require 'pp'
require 'ostruct'
require 'yaml'
require 'jekyll'
require 'date'
require 'digest/md5'
require 'action_view'
require 'net/http'
require 'net/https'
require 'feedparser'
require 'uri'

include ActionView::Helpers::DateHelper

# From http://api.rubyonrails.org/classes/ActiveSupport/CoreExtensions/Hash/Keys.html
class Hash
  def stringify_keys!
    keys.each do |key|
      self[key.to_s] = delete(key)
    end
    self
  end
end




#
# Parses a rss/atom feed and returns items as an array.
#
class RSSFeed
  DEFAULT_TTL = 600
  class << self
    def tag(url, count = 15, ttl=DEFAULT_TTL)
      links = []
      url = "#{url}"
      uri=URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      if uri.scheme == "https"
	http.use_ssl = true
	http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      f = FeedParser::Feed::new(response.body)
      f.items.take(count.to_i).each do |i|
        item = OpenStruct.new
	item.title = i.title
	item.link = i.link
	item.date = i.date
	item.day = time_ago_in_words(i.date)
	item.description = i.content
        links << item
      end
      links
    end
  end
end

# 
# Cached version of the RSSFeed Jekyll tag.
#
class CachedRSSFeed < RSSFeed
  DEFAULT_TTL = 600
  CACHE_DIR = '_rssfeed_cache'
  class << self
    def tag(url, count = 15, ttl = DEFAULT_TTL)
      ttl = DEFAULT_TTL if ttl.nil?
      cache_key = "#{url}_#{count}"
      cache_file = File.join(CACHE_DIR, Digest::MD5.hexdigest(cache_key) + '.yml')
      FileUtils.mkdir_p(CACHE_DIR) if !File.directory?(CACHE_DIR)
      age_in_seconds = Time.now - File.stat(cache_file).mtime if File.exist?(cache_file)
      if age_in_seconds.nil? || age_in_seconds > ttl
        result = super(url, count)
        File.open(cache_file, 'w') { |out| YAML.dump(result, out) }
      else
        result = YAML::load_file(cache_file)
      end
      result
    end
  end
end

module Jekyll
  class RSSFeedTag < Liquid::Block

    include Liquid::StandardFilters
    Syntax = /(#{Liquid::QuotedFragment}+)?/ 

    def initialize(tag_name, markup, tokens)
      @variable_name = 'item'
      @attributes = {}
      
      # Parse parameters
      if markup =~ Syntax
        markup.scan(Liquid::TagAttributes) do |key, value|
          #p key + ":" + value
          @attributes[key] = value
        end
      else
        raise SyntaxError.new("Syntax Error in 'rssfeed' - Valid syntax: rssfeed uid:x count:x]")
      end

      @ttl = @attributes.has_key?('ttl') ? @attributes['ttl'].to_i : nil
      @url = @attributes['url']
      @count = @attributes['count']
      @name = 'item'

      super
    end

    def render(context)
      context.registers[:rssfeed] ||= Hash.new(0)
    
      if @ttl
        collection = CachedRSSFeed.tag(@url, @count, @ttl)
      else
        collection = RSSFeed.tag(@url, @count)
      end

      length = collection.length
      result = []
              
      # loop through found items and render results
      context.stack do
        collection.each_with_index do |item, index|
          attrs = item.send('table')
          context[@variable_name] = attrs.stringify_keys! if attrs.size > 0
          context['forloop'] = {
            'name' => @name,
            'length' => length,
            'index' => index + 1,
            'index0' => index,
            'rindex' => length - index,
            'rindex0' => length - index -1,
            'first' => (index == 0),
            'last' => (index == length - 1) }

          result << render_all(@nodelist, context)
        end
      end
      result
    end
  end
end

Liquid::Template.register_tag('rssfeed', Jekyll::RSSFeedTag)

