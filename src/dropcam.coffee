# Description:
#   Allows Hubot to fetch Dropcam stills.
#
# Dependencies:
#   "aws2js": "0.8.3"
#
# Configuration:
#     HUBOT_DROPCAM_USERNAME, HUBOT_DROPCAM_PASSWORD, HUBOT_DROPCAM_BLACKLIST
#     HEROKU_URL
#     HUBOT_DROPCAM_S3_ACCESS_KEY_ID, HUBOT_DROPCAM_S3_SECRET_ACCESS_KEY, HUBOT_DROPCAM_S3_BUCKET
#
# Commands:
#   hubot dropcam me - Get a dropcam image
#   hubot dropcam list - List the dropcams available
#
# Author:
#   RSully
#

fs = require 'fs'
aws = require 'aws2js'
crypto = require 'crypto'
request = require 'request'

randomString = (len, charSet) ->
  charSet = charSet or "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  randString = ""
  i = 0

  while i < len
    randomPoz = Math.floor(Math.random() * charSet.length)
    randString += charSet[randomPoz..randomPoz + 1]
    i++
  return randString

dcTimeToFilename = (time) ->
  "dropcam-#{time}.jpg"

hubotListenAddr = ->
  return process.env.HEROKU_URL

dcUuidIsBlacklisted = (uuid) ->
  blacklist = process.env.HUBOT_DROPCAM_BLACKLIST || ''
  blacklist = blacklist.split ','
  return blacklist.indexOf(uuid) != -1

class Dropcam
  constructor: (@logger) ->
    @cookies = request.jar()
    @dcUserAgent = 'Python-urllib/2.6'

    @dcApiPath = 'https://www.dropcam.com/api/v1/'

    @dcLoginUrl = @dcApiPath + 'login.login'
    @dcCamerasUrl = @dcApiPath + 'cameras.get_visible'
    @dcImageUrl = @dcApiPath + 'cameras.get_image'

  mergeOptions: (options) ->
    options.jar = @cookies
#    options.pool = false
    if not options.headers?
      options.headers = {}
    options.headers['user-agent'] = @dcUserAgent
    return options

  login: (callback, username, password) ->
    # callback(err)

    options = @mergeOptions {
      url: @dcLoginUrl,
      qs: {
        username: username,
        password: password
      }
    }

    request options, (err, res, body) ->
      failed = err or res.statusCode != 200
      callback failed

  cameras: (callback) ->
    # callback(err, cameras)

    # If this breaks look into query(group_cameras: true) - I think the handling code is all set
    options = @mergeOptions {
      url: @dcCamerasUrl
    }

    self = @

    request options, (err, res, body) ->
      bodyJson = JSON.parse(body)
      failed = err or res.statusCode != 200 or bodyJson.status == 403
      if failed
        self.logger.error "Got error from dropcam.cameras: #{err}"
        callback failed, null
        return

      cameras = {}
      for item in bodyJson.items
        if item.owned?
          for owned in item.owned
            cameras[owned.uuid] = owned
        else
          cameras[item.uuid] = item
      callback failed, cameras

  image: (callback, camera, width = 720) ->
    # callback(err, buffer)

    options = @mergeOptions {
      url: @dcImageUrl,
      qs: {
        uuid: camera.uuid,
        width: width
      },
      encoding: null
    }

    self = @

    request options, (err, res, body) ->
      if err or res.statusCode != 200
        self.logger.error "Got error (or non-200) from dropcam.image: #{err}"
        callback true, null
      callback (body.length < 1), body


module.exports = (robot) ->

  # Check env vars

  requiredEnvs = [
    'HUBOT_DROPCAM_USERNAME',
    'HUBOT_DROPCAM_PASSWORD'
  ]

  requiredEnvMissing = false
  for requiredEnv in requiredEnvs
    unless process.env[requiredEnv]?
      robot.logger.warning "The '#{requiredEnv}' enviornment variable not set"
      requiredEnvMissing = true
  if requiredEnvMissing
    robot.logger.error 'Dropcam not loaded'
    return

  dropcamClient = new Dropcam robot.logger

  if process.env.HUBOT_DROPCAM_S3_ACCESS_KEY_ID?
    s3 = aws.load('s3', process.env.HUBOT_DROPCAM_S3_ACCESS_KEY_ID, process.env.HUBOT_DROPCAM_S3_SECRET_ACCESS_KEY)
    s3.setBucket(process.env.HUBOT_DROPCAM_S3_BUCKET)

  robot.respond /(dropcam)(( )(list))/i, (msg) ->

    handleCameras = (err, cameras) ->
      if err
        msg.send 'Dropcam devices not found'
        return

      camList = []

      for uuid, camera of cameras
        # Check blacklist
        if dcUuidIsBlacklisted uuid
          continue

        cTitle = camera.title
        if camera.description
          cTitle += ' - ' + camera.description

        cOnline = (if camera.is_online then 'on' else 'off') + 'line'

        camList.push("#{cTitle} (#{cOnline})")

      msg.send camList.join("\n")

      if process.env.DEBUG
        msg.send JSON.stringify(cameras)

    handleLogin = (err) ->
      if err
        msg.send "Dropcam auth failed"
        return
      dropcamClient.cameras handleCameras

    # TODO: refactor so login happens automatically, perhaps - not until we need to scale though
    dropcamClient.login handleLogin, process.env.HUBOT_DROPCAM_USERNAME, process.env.HUBOT_DROPCAM_PASSWORD

  robot.respond /(dropcam)(( )(me))(( )(.*))?/i, (msg) ->

    dcCameraTitle = msg.match[7]
    dcDefaultCamera = process.env.HUBOT_DROPCAM_DEFAULT_CAMERA

    robot.logger.info "Dropcam image requested by #{JSON.stringify(msg.message.user)}"

    handleImage = (err, buffer) ->

      if err
        msg.send "No image for you (error)"
        return

      dcTime = new Date().getTime()

      if s3
        s3hash = crypto.createHash 'sha1'
        s3hash.update 'img-dropcam-' + randomString 10
        s3file = dcTime + '-' + s3hash.digest('hex') + '.jpg'

        imageUploaded = (err, result) ->
          if err
            msg.send "Failed to upload image"
            return
          msg.send 'https://' + process.env.HUBOT_DROPCAM_S3_BUCKET + '.s3.amazonaws.com/' + s3file

        headers = {
          "content-type": "image/jpeg"
        }

        s3.putBuffer(s3file, buffer, 'public-read', headers, imageUploaded)
        return

      # Default without s3:

      fs.writeFile dcTimeToFilename(dcTime), buffer, (err) ->
        if err
          msg.send "Couldn't save the image"
          return
        msg.send hubotListenAddr() + '/dropcam/image.jpg?ts=' + encodeURIComponent(dcTime)

    handleCameras = (err, cameras) ->
      if err
        msg.send 'Dropcam devices not found'
        return

      dcCam = null
      for uuid, camera of cameras
        # Check blacklist
        if dcUuidIsBlacklisted uuid
          continue
        if (not dcCameraTitle and not dcDefaultCamera) or (uuid is dcDefaultCamera) or (camera.title.toLowerCase() is dcCameraTitle.toLowerCase())
          dcCam = camera
          break
      unless dcCam
        msg.send 'Dropcam not found'
        return
      unless dcCam.is_online
        msg.send 'Dropcam is offline'
        return

      robot.logger.info 'Requesting Dropcam image'
      dropcamClient.image handleImage, dcCam, 720

    handleLogin = (err) ->
      if err
        msg.send "Dropcam auth failed"
        return
      dropcamClient.cameras handleCameras

    # TODO: refactor so login happens automatically, perhaps - not until we need to scale though
    dropcamClient.login handleLogin, process.env.HUBOT_DROPCAM_USERNAME, process.env.HUBOT_DROPCAM_PASSWORD

  # Handle HTTP requests when S3 is disabled
  unless s3
    robot.router.get '/dropcam/image.jpg', (req, res) ->
      fs.readFile dcTimeToFilename(req.query['ts']), (err, data) ->
        if err
          res.end ''
          return
        res.end data

