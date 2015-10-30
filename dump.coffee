fs      = require 'fs'
request = require 'request'
async   = require 'async'
$       = require 'cheerio'
_       = require 'lodash'

get_page_urls = (cb)->
  console.log "Getting page URLs"

  request 'http://www.archivoprisma.com.ar/ultimos-digitalizados/', (err, response, body)->
    if err
      return cb err

    total_pages = $(body).find('nav.pagination a:last-child').first().attr('href').replace(/[^\d]/gi,'')
    total_pages = parseInt total_pages

    page_urls = for page_number in [1..total_pages]
      "http://www.archivoprisma.com.ar/ultimos-digitalizados/page/#{page_number}/"

    cb null, page_urls

extract_video_urls = (page_url, cb)->
  console.log "Extracting video URLs from #{page_url}"

  request page_url, (err, response, body)->
    if err
      return cb err

    video_urls = []

    $(body).find('.post-title a').each( (idx, a)-> video_urls.push $(a).attr('href') )

    cb null, video_urls

extract_meta = ($body, type)->
  $body.find(".iconbox_content_title:contains(#{type})").parents('.iconbox_content').find('.iconbox_content_container').text().trim()

extract_tags = ($body, type)->
  tags = []
  $body.find("strong:contains(#{type})").parents('.blog-tags.minor-meta').find('a').each( (idx, a)-> tags.push $(a).text().trim() )
  return tags

extract_video_data = (video_url, cb)->
    console.log "Extracting video data from #{video_url}"

    request video_url, (err, response, body)->
      if err
        return cb err

      $body = $(body)

      video =
        url: video_url
        id: parseInt $body.find('link[rel=shortlink]').attr('href').split('=').pop()
        title: $body.find('.main-title').text().trim()
        where: extract_meta $body, 'Dónde'
        when: extract_meta $body, 'Cuándo'
        who: _.invoke extract_meta($body, 'Quién').split(','), 'trim'
        description: $body.find('blockquote').text().trim()
        sources: extract_tags $body, 'Fuente'
        categories: extract_tags $body, 'Categorías'
        tags: extract_tags $body, 'Etiquetas'
        media: []

      player_script = $body.find('.jwplayer').next().find('script').text()

      if match = player_script.match(/playlist":"([^"]+)"/)
        video.media.push
          type: 'playlist'
          content: match[1]

      else if match = player_script.match(/file":"([^"]+)"/)
        video.media.push
          type: 'video'
          title: ''
          thumbnail: ''
          content: match[1]

      cb null, video

replace_video_playlist = (video, cb)->

  if video.media.length is 0 or video.media[0].type isnt 'playlist'
    return cb null, video

  console.log "Replacing media playlist in video ##{video.id}"

  request video.media[0].content, (err, response, body)->
    $body = $(body)

    video.media = []

    $body.find('item').each (idx, item)->
      video.media.push
        title: $body.find('title').text()
        content: $body.find('media\\:content').attr('url')
        thumbnail: $body.find('media\\:thumbnail').attr('url')

    console.log "Added #{video.media.length} items to video ##{video.id}"

    cb null, video

parallel_limit = 20

async.waterfall [

    get_page_urls

    (page_urls, cb)->
      console.log "Found #{page_urls.length} pages"
      async.concat page_urls, extract_video_urls, cb

    (video_urls, cb)->
      console.log "Found #{video_urls.length} video pages"
      async.mapLimit video_urls, parallel_limit, extract_video_data, cb

    (videos, cb)->
      async.mapLimit videos, parallel_limit, replace_video_playlist, cb

    (videos, cb)->
      fs.writeFile 'rta.json', JSON.stringify(videos), cb

  ], (err, res)->
    console.log err or "Done"
