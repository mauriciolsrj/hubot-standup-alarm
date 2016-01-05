# Description:
#   Have Hubot remind you to do standups.
#   hh:mm must be in the same timezone as the server Hubot is on. Probably UTC.
#
#   This is configured to work for Hipchat. You may need to change the 'create standup' command
#   to match the adapter you're using.
#
# Configuration:
#  HUBOT_STANDUP_PREPEND
#
# Commands:
#   hubot standup help - See a help document explaining how to use.
#   hubot create standup hh:mm - Creates a standup at hh:mm every weekday for this room
#   hubot create standup hh:mm UTC+2 - Creates a standup at hh:mm every weekday for this room (relative to UTC)
#   hubot list standups - See all standups for this room
#   hubot list standups in every room - See all standups in every room
#   hubot delete hh:mm standup - If you have a standup at hh:mm, deletes it
#   hubot delete all standups - Deletes all standups for this room.
#
# Dependencies:
#   underscore
#   cron

###jslint node: true###

cronJob = require('cron').CronJob
_ = require('underscore')

module.exports = (robot) ->
  # Compares current time to the time of the standup
  # to see if it should be fired.

  standupShouldFire = (standup) ->
    standupTime = standup.time
    utc = standup.utc
    now = new Date
    currentHours = undefined
    currentMinutes = undefined
    if utc
      currentHours = now.getUTCHours() + parseInt(utc, 10)
      currentMinutes = now.getUTCMinutes()
      if currentHours > 23
        currentHours -= 23
    else
      currentHours = now.getHours()
      currentMinutes = now.getMinutes()
    standupHours = standupTime.split(':')[0]
    standupMinutes = standupTime.split(':')[1]
    try
      standupHours = parseInt(standupHours, 10)
      standupMinutes = parseInt(standupMinutes, 10)
    catch _error
      return false
    if standupHours == currentHours and standupMinutes == currentMinutes
      return true
    false

  # Returns all standups.

  getStandups = ->
    robot.brain.get('standups') or []

  # Returns just standups for a given room.

  getStandupsForRoom = (room) ->
    _.where getStandups(), room: room

  # Gets all standups, fires ones that should be.

  checkStandups = ->
    standups = getStandups()
    _.chain(standups).filter(standupShouldFire).pluck('room').each doStandup
    return

  # Fires the standup message.

  doStandup = (room) ->
    message = PREPEND_MESSAGE + _.sample(STANDUP_MESSAGES)
    robot.messageRoom room, message
    return

  # Finds the room for most adaptors

  findRoom = (msg) ->
    room = msg.envelope.room
    if _.isUndefined(room)
      room = msg.envelope.user.reply_to
    room

  # Stores a standup in the brain.

  saveStandup = (room, time, utc) ->
    standups = getStandups()
    newStandup = 
      time: time
      room: room
      utc: utc
    standups.push newStandup
    updateBrain standups
    return

  # Updates the brain's standup knowledge.

  updateBrain = (standups) ->
    robot.brain.set 'standups', standups
    return

  clearAllStandupsForRoom = (room) ->
    standups = getStandups()
    standupsToKeep = _.reject(standups, room: room)
    updateBrain standupsToKeep
    standups.length - (standupsToKeep.length)

  clearSpecificStandupForRoom = (room, time) ->
    standups = getStandups()
    standupsToKeep = _.reject(standups,
      room: room
      time: time)
    updateBrain standupsToKeep
    standups.length - (standupsToKeep.length)

  'use strict'
  # Constants.
  STANDUP_MESSAGES = [
    'Daily meeting pessoal!!! Partiu partiu!'
    'Opa! Chegou a hora da nossa reuniãozinha diária.'
    'É hora da nossa daily!'
    'Pessoal, vamos fazer um daily rapidinho até porque hoje está meio corrido pra mim.'
    'Humanos, é hora da reunião diária!'
    'Hora da reunião diária! Vamos, vamos, vamos!'
  ]
  PREPEND_MESSAGE = process.env.HUBOT_STANDUP_PREPEND or ''
  if PREPEND_MESSAGE.length > 0 and PREPEND_MESSAGE.slice(-1) != ' '
    PREPEND_MESSAGE += ' '
  # Check for standups that need to be fired, once a minute
  # Monday to Friday.
  new cronJob('1 * * * * 1-5', checkStandups, null, true)
  robot.respond /excluir daily/i, (msg) ->
    standupsCleared = clearAllStandupsForRoom(findRoom(msg))
    msg.send 'Excluído um total de ' + standupsCleared + ' registro' + (if standupsCleared == 1 then '' else 's') + '. No more standups for you.'
    return
  robot.respond /excluir daily ([0-5]?[0-9]:[0-5]?[0-9])/i, (msg) ->
    time = msg.match[1]
    standupsCleared = clearSpecificStandupForRoom(findRoom(msg), time)
    if standupsCleared == 0
      msg.send 'Boa tentativa mané, mas você não tem nenhuma daily nesse horário.' + time
    else
      msg.send 'Cancelei a reunião das ' + time
    return
  robot.respond /criar daily ((?:[01]?[0-9]|2[0-4]):[0-5]?[0-9])$/i, (msg) ->
    time = msg.match[1]
    room = findRoom(msg)
    saveStandup room, time
    msg.send 'Ok, pode deixar que a partir de agora eu lembro vocês da daily às ' + time
    return
  robot.respond /criar daily ((?:[01]?[0-9]|2[0-4]):[0-5]?[0-9]) UTC([+-]([0-9]|1[0-3]))$/i, (msg) ->
    time = msg.match[1]
    utc = msg.match[2]
    room = findRoom(msg)
    saveStandup room, time, utc
    msg.send 'Ok, pode deixar que a partir de agora eu lembro vocês da daily às ' + time + ' UTC' + utc
    return
  robot.respond /listar daily$/i, (msg) ->
    standups = getStandupsForRoom(findRoom(msg))
    if standups.length == 0
      msg.send 'É constrangedor dizer isso, mas você ainda não marcou nenhuma daily por aqui.'
    else
      standupsText = [ 'Aqui estão suas reuniÕes diárias:' ].concat(_.map(standups, (standup) ->
        if standup.utc
          standup.time + ' UTC' + standup.utc
        else
          standup.time
      ))
      msg.send standupsText.join('\n')
    return
  robot.respond /listar daily por canal/i, (msg) ->
    standups = getStandups()
    if standups.length == 0
      msg.send 'Não, porque não tem nenhuma..'
    else
      standupsText = [ 'Aqui estão as reuniões por canal:' ].concat(_.map(standups, (standup) ->
        'Canal: ' + standup.room + ', Horário: ' + standup.time
      ))
      msg.send standupsText.join('\n')
    return
  robot.respond /standup help/i, (msg) ->
    message = []
    message.push 'I can remind you to do your daily standup!'
    message.push 'Use me to create a standup, and then I\'ll post in this room every weekday at the time you specify. Here\'s how:'
    message.push ''
    message.push robot.name + ' create standup hh:mm - I\'ll remind you to standup in this room at hh:mm every weekday.'
    message.push robot.name + ' create standup hh:mm UTC+2 - I\'ll remind you to standup in this room at hh:mm every weekday.'
    message.push robot.name + ' list standups - See all standups for this room.'
    message.push robot.name + ' list standups in every room - Be nosey and see when other rooms have their standup.'
    message.push robot.name + ' delete hh:mm standup - If you have a standup at hh:mm, I\'ll delete it.'
    message.push robot.name + ' delete all standups - Deletes all standups for this room.'
    msg.send message.join('\n')
    return
  return
