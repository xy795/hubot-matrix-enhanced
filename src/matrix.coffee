# Description:
#   Enhanced matrix adapter for Hubot
#
# Configuration:
#   Can either be done via json config file (key: matrix) or environment variables
#
#   ENV                         JSON          Description
#   HUBOT_MATRIX_HOST           host          the host of the matrix server to connect to
#   HUBOT_MATRIX_USER           user          the hubot user for connecting to matrix
#   HUBOT_MATRIX_ACCESS_TOKEN   access_token  access token for token authentication
#   HUBOT_MATRIX_PASSWORD       password      password for password authentication

try
  {Robot,Adapter,TextMessage,User} = require 'hubot'
catch
  prequire = require('parent-require')
  {Robot,Adapter,TextMessage,User} = prequire 'hubot'

sdk = require 'matrix-js-sdk'
request = require 'request'
sizeOf = require 'image-size'
deferred = require 'deferred'
config = require 'config'

ENV_PREFIX = "HUBOT_MATRIX"
JSON_PREFIX = "matrix"

unless localStorage?
  {LocalStorage} = require('node-localstorage')
  localStorage = new LocalStorage('./hubot-matrix.localStorage')

class Matrix extends Adapter
  constructor: ->
    super

  loadConfigValue: (key, default_value=undefined ) ->
    result = process.env["#{ENV_PREFIX}_#{key.toUpperCase()}"]
    if result
      return result

    json_key = "#{JSON_PREFIX}.#{key}"
    if config.has(json_key)
      return config.get(json_key)

    default_value

  handleUnknownDevices: (err) ->
    for stranger, devices of err.devices
      for device, _ of devices
        @robot.logger.info "Acknowledging #{stranger}'s device #{device}"
        @client.setDeviceKnown(stranger, device)

  send: (envelope, strings...) ->
    @client.getRoomIdForAlias envelope.room, (err, data) =>
      unless err
        envelope.room = data.room_id

      for str in strings
        @robot.logger.info "Sending to #{envelope.room}: #{str}"
        if /^(f|ht)tps?:\/\//i.test(str)
          @sendURL envelope, str
        else
          @client.sendNotice(envelope.room, str).catch (err) =>
            if err.name == 'UnknownDeviceError'
              @handleUnknownDevices err
              @client.sendNotice(envelope.room, str)

  notification: (envelope, strings...) ->
    for str in strings
      @robot.logger.info "Sending to #{envelope.room}: #{str}"
      @client.sendTextMessage(envelope.room, str).catch (err) =>
        if err.name == 'UnknownDeviceError'
          @handleUnknownDevices err
          @client.sendTextMessage(envelope.room, str)

  notificationHtml: (envelope, strings) ->
    stringText = JSON.parse(JSON.stringify(strings)).string
    stringHtml = JSON.parse(JSON.stringify(strings)).stringHtml
    console.dir(strings)
    console.dir([stringText, stringHtml])
    @robot.logger.info "Sending to #{envelope.room}: #{stringText} #{stringHtml}"
    @client.sendHtmlMessage(envelope.room, stringText, stringHtml).catch (err) =>
      if err.name == 'UnknownDeviceError'
        @handleUnknownDevices err
        @client.sendHtmlMessage(envelope.room, stringText, stringHtml)

  emote: (envelope, strings...) ->
    for str in strings
      @client.sendEmoteMessage(envelope.room, str).catch (err) =>
        if err.name == 'UnknownDeviceError'
          @handleUnknownDevices err
          @client.sendEmoteMessage(envelope.room, str)

  reply: (envelope, strings...) ->
    for str in strings
      @send envelope, "#{envelope.user.name}: #{str}"

  topic: (envelope, strings...) ->
    for str in strings
      @client.sendStateEvent envelope.room, "m.room.topic", {
        topic: str
      }, ""

  sendURL: (envelope, url) ->
    @robot.logger.info "Downloading #{url}"
    request url: url, encoding: null, (error, response, body) =>
      if error
        @robot.logger.info "Request error: #{JSON.stringify error}"
      else if response.statusCode == 200
        try
          dims = sizeOf body
          @robot.logger.info "Image has dimensions #{JSON.stringify dims}, size #{body.length}"
          dims.type = 'jpeg' if dims.type == 'jpg'
          info = { mimetype: "image/#{dims.type}", h: dims.height, w: dims.width, size: body.length }
          @client.uploadContent(body, name: url, type: info.mimetype, rawResponse: false, onlyContentUri: true).done (content_uri) =>
            @client.sendImageMessage(envelope.room, content_uri, info, url).catch (err) =>
              if err.name == 'UnknownDeviceError'
                @handleUnknownDevices err
                @client.sendImageMessage(envelope.room, content_uri, info, url)
        catch error
          @robot.logger.info error.message
          @send envelope, " #{url}"

  newRoom: (envelope, roomName, visibility) ->
    vis = if visibility then "public" else "private"
    sender = envelope.user.id
    @robot.logger.info("Received createRoom request from #{sender} with attributes name: #{roomName} visibility: #{vis}")
    options = { room_alias_name: roomName, name: roomName, visibility: vis, invite: [sender] }
    @client.createRoom(options,
      (err, data) =>
        delete envelope["message"]
        @robot.logger.info(data)
        if err
          @robot.reply(envelope, "Could not create room: #{err.message}")
        else
          content = {users: {}}
          content.users["#{sender}"] = 100
          content.users["#{@user_id}"] = 100
          @client.sendStateEvent(data.room_id, "m.room.power_levels", content, undefined, (err, data) =>
            if err
              @robot.reply(envelope, "Could not promote #{sender} in new room #{roomName}: #{err.message}")
            else
              @robot.logger.info("Successfully created room #{roomName} for #{sender}")
          ))


  load_config: ->
    loginData = {}
    loginData.baseUrl = @loadConfigValue('host', 'https://matrix.org')

    @robot.logger.info "Run #{@robot.name} with matrix server #{loginData.baseUrl}"

    user = @loadConfigValue('user', @robot.name)
    re = new RegExp("^@(.*):#{loginData.baseUrl.replace(/[-[\]{}()*+?.,\\^$|]/g, "\\$&")}$")
    unless re.test(user)
      user = "@#{user}:#{loginData.baseUrl.replace(/https?:\/\//, '')}"
    loginData.userId = user
    loginData.accessToken = @loadConfigValue('access_token')

    def = deferred()

    if loginData.accessToken
      def.resolve loginData
    else
      password = @loadConfigValue('password')
      client = sdk.createClient(loginData.baseUrl)
      client.login 'm.login.password', { user: user, password: password }, (err, data) =>
        if err
          def.reject err
        else
          @robot.logger.info "Logged in #{data.user_id} on device #{data.device_id} on server #{loginData.baseUrl}"
          delete loginData.user
          loginData.accessToken = data.access_token
          loginData.userId = data.user_id
          loginData.deviceId = data.device_id
          def.resolve loginData
    def.promise

  run: ->
    @load_config().then (data) =>
      @host_url = data.baseUrl
      data.sessionStore = new sdk.WebStorageSessionStore(localStorage)
      @client = sdk.createClient data
    .then (data) =>
      @user_id = @client.getUserId()
      @client.on 'sync', (state, prevState, data) =>
        switch state
          when "PREPARED"
            @robot.logger.info "Synced #{@client.getRooms().length} rooms"
            @emit 'connected'
      @client.on 'Room.timeline', (event, room, toStartOfTimeline) =>
        if event.getType() == 'm.room.message' and toStartOfTimeline == false
          @client.setPresence "online"
          message = event.getContent()
          name = event.getSender()
          user = @robot.brain.userForId name
          user.room = room.roomId
          if user.name != @user_id
            @robot.logger.info "Received message: #{JSON.stringify message} in room: #{user.room}, from: #{user.name}."
            @receive new TextMessage user, message.body if message.msgtype == "m.text"
            @client.sendReadReceipt(event) if message.msgtype != "m.text" or message.body.indexOf(@robot.name) != -1
      @client.on 'RoomMember.membership', (event, member) =>
        if member.membership == 'invite' and member.userId == @user_id
          @client.joinRoom(member.roomId).done =>
            @robot.logger.info "Auto-joined #{member.roomId}"
      @client.startClient 0
    .catch (err) =>
      @robot.logger.error 'Error during authentication', err


exports.use = (robot) ->
  new Matrix robot
