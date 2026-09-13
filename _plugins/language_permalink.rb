# frozen_string_literal: true

# Each build reads only one language, so every Jekyll feature (pagination,
# archives, search, related posts and previous/next links) uses the same set.
[:after_init, :after_reset].each do |event|
  Jekyll::Hooks.register :site, event do |site|
    language = site.config.fetch('post_language')
    raise "Unsupported post language: #{language}" unless %w[en jp].include?(language)

    site.exclude |= ["_posts/#{language == 'jp' ? 'en' : 'jp'}"]
  end
end

Jekyll::Hooks.register :site, :post_read do |site|
  site.pages.each do |page|
    page.data['title'] = site.data['locales'][site.config['lang']]['not_found_title'] if page.data['permalink'] == '/404.html'
  end

  site.posts.docs.each do |post|
    post.data['lang'] = site.config['lang']
    # baseurl supplies /jp or /en. Keep the existing public post URLs while
    # leaving the source front matter and post bodies untouched.
    post.data['permalink'] = "/#{post.data['slug']}/"
  end
end
