# Nim module for working with playlist files.

# Written by Adam Chesak & tandy1000.
# Released under the MIT open source license.


import std/[strutils, xmlparser, xmltree, streams, unicode]


type
  PlaylistTrack* = ref object
    track: int
    file, title, length: string

  PlaylistM3U* = ref object
    numberOfEntries: int
    tracks: seq[PlaylistM3UTrack]

  PlaylistM3UTrack* = PlaylistTrack

  PlaylistPLS* = ref object
    numberOfEntries, version: int
    tracks: seq[PlaylistPLSTrack]

  PlaylistPLSTrack* = PlaylistTrack

  XSPFObject* = ref object of RootObj
    title, creator, annotation, info, location, identifier, image: string

  PlaylistXSPF* = ref object of XSPFObject
    numberOfEntries, version: int
    tracks: seq[PlaylistXSPFTrack]
    date, license: string
    meta: seq[PlaylistXSPFMeta]

  PlaylistXSPFTrack* = ref object of XSPFObject
    track: int
    album, duration: string

  PlaylistXSPFMeta* = ref object
    rel, value: string

  Playlist* = ref object
    format: PlaylistFormat
    m3u: PlaylistM3U  # Note that only one of these three properties will be set at any time,
    pls: PlaylistPLS  # based on the value of the ``format`` property. The other properties
    xspf: PlaylistXSPF  # will not be set and should not be used.
    # jspf: PlaylistJSPF  # will not be set and should not be used.


  PlaylistSimple* = ref object
    numberOfEntries: int
    tracks: seq[PlaylistSimpleTrack]

  PlaylistSimpleTrack* = PlaylistTrack

  PlaylistFormat* {.pure.} = enum
    M3U, PLS, XSPF, JSPF

  PlaylistFormatError* = object of Exception


proc normalizePlaylist(playlist: string): seq[string] =
  ## Internal proc. Splits the playlist into lines and gets
  ## rid of excess space.

  var
    lines: seq[string] = playlist.splitLines()
    linesNew: seq[string] = @[]
    line: string

  for i in lines:
    line = strutils.strip(i, leading = true, trailing = true)
    if line == "":
      continue
    linesNew.add(line)

  return linesNew


proc normalizeLine(line: seq[string]): seq[string] =
  ## Internal proc. Gets rid of excess space.

  var
    lineNew: seq[string] = @[]
    item: string
  for i in line:
    item = strutils.strip(i, leading = true, trailing = true)
    if item == "":
      continue
    lineNew.add(item)

  return lineNew


proc parseM3U*(playlist: string): PlaylistM3U =
  ## Parses a M3U playlist from the given string.

  # Make sure the playlist is in the correct format.
  var lines: seq[string] = normalizePlaylist(playlist)
  if lines[0] != "#EXTM3U":
    raise newException(PlaylistFormatError, "parseM3U(): playlist is not in M3U format")

  # Parse the playlist.
  var
    playlist: PlaylistM3U = PlaylistM3U(tracks: @[])
    currentIndex: int = 1
    currentTrack: int = 1
  while currentIndex < high(lines):
    var
      info: string = lines[currentIndex][8..high(lines[currentIndex])]
      infoItems: seq[string] = normalizeLine(info.split(","))
      track: PlaylistM3UTrack = PlaylistM3UTrack()
    track.track = currentTrack
    track.length = infoItems[0]
    track.title = infoItems[1]
    track.file = lines[currentIndex + 1]

    currentTrack += 1
    currentIndex += 2
    playlist.tracks.add(track)

  playlist.numberOfEntries = len(playlist.tracks)

  return playlist


proc parseM3U*(playlist: File): PlaylistM3U =
  ## Parses a M3U playlist from the given file.

  var fileContents: string = playlist.readAll()
  playlist.close()

  return parseM3U(fileContents)


proc parsePLS*(playlist: string): PlaylistPLS =
  ## Parses a PLS playlist from the given string.

  # Make sure the playlist is in the correct format.
  var lines: seq[string] = normalizePlaylist(playlist)
  if unicode.toLower(lines[0]) != "[playlist]":
    raise newException(PlaylistFormatError, "parsePLS(): playlist is not in PLS format")

  # Parse the playlist.
  var
    titleList: seq[seq[string]] = @[]
    fileList: seq[seq[string]] = @[]
    lengthList: seq[seq[string]] = @[]
    playlist: PlaylistPLS = PlaylistPLS(tracks: @[])
    line: seq[string]
    lineFirst: string
  for i in lines:
    line = normalizeLine(i.split("="))
    lineFirst = unicode.toLower(line[0])
    if lineFirst == "numberofentries":
      playlist.numberOfEntries = parseInt(line[1])
      continue
    elif lineFirst == "version":
      if line[1] != "2":
        raise newException(PlaylistFormatError, "parsePLS(): version entry must be 2")
      else:
        playlist.version = parseInt(line[1])
      continue
    if lineFirst.startsWith("title"):
      titleList.add(@[line[0][5..5], line[1]])
    elif lineFirst.startsWith("file"):
      fileList.add(@[line[0][4..4], line[1]])
    elif lineFirst.startsWith("length"):
      lengthList.add(@[line[0][6..6], line[1]])

  # Append the tracks.
  if len(titleList) != len(fileList):
    raise newException(PlaylistFormatError, "parsePLS(): title fields and file fields do not match")
  var
    currentTrack: int = 1
    track: PlaylistPLSTrack
  for j in 0..high(titleList):
    track = PlaylistPLSTrack()
    track.track = currentTrack
    for k in 0..high(titleList):
      if parseInt(titleList[k][0]) == currentTrack:
        track.title = titleList[k][1]
        break
    for k in 0..high(fileList):
      if parseInt(fileList[k][0]) == currentTrack:
        track.file = fileList[k][1]
        break
    for k in 0..high(lengthList):
      if parseInt(lengthList[k][0]) == currentTrack:
        track.length = lengthList[k][1]
        break
    playlist.tracks.add(track)
    currentTrack += 1

  return playlist


proc parsePLS*(playlist: File): PlaylistPLS =
  ## Parses a PLS playlist from the given file.

  var fileContents: string = playlist.readAll()
  playlist.close()

  return parsePLS(fileContents)


proc parseXSPF*(playlist: string): PlaylistXSPF =
  ## Parses an XSPF playlist from the given string.

  # Make sure the playlist is in the correct format.
  # Not a good way to check this.
  var chk: string = strutils.strip(playlist, leading = true)
  if not chk.startsWith("<xml") and not chk.startsWith("<playlist"):
    raise newException(PlaylistFormatError, "parseXSPF(): playlist is not in XSPF format")

  # Parse the playlist.
  var
    pl: PlaylistXSPF  = PlaylistXSPF()
    data: XmlNode = parseXML(newStringStream(playlist)).child("playlist")
  pl.version = parseInt(data.attr("version"))

  if data.child("title") != nil:
    pl.title = data.child("title").innerText
  if data.child("creator") != nil:
    pl.creator = data.child("creator").innerText
  if data.child("annotation") != nil:
    pl.annotation = data.child("annotation").innerText
  if data.child("info") != nil:
    pl.info = data.child("info").innerText
  if data.child("location") != nil:
    pl.location = data.child("location").innerText
  if data.child("identifier") != nil:
    pl.identifier = data.child("identifier").innerText
  if data.child("image") != nil:
    pl.image = data.child("image").innerText
  if data.child("date") != nil:
    pl.date = data.child("date").innerText
  if data.child("license") != nil:
    pl.license = data.child("license").innerText
  var
    meta: seq[XmlNode] = data.findAll("meta")
    metaSeq = newSeq[PlaylistXSPFMeta](len(meta))
    me: PlaylistXSPFMeta
  for i in 0..high(meta):
    me = PlaylistXSPFMeta()
    me.rel = meta[i].attr("rel")
    me.value = meta[i].innerText
    metaSeq[i] = me
  pl.meta = metaSeq

  var
    tracks: seq[XMLNode] = data.child("trackList").findAll("track")
    trackSeq = newSeq[PlaylistXSPFTrack](len(tracks))
    t: PlaylistXSPFTrack
  for i in 0..high(tracks):
    t = PlaylistXSPFTrack()
    t.track = i
    t.location = tracks[i].child("location").innerText
    t.title = tracks[i].child("title").innerText
    if tracks[i].child("identifier") != nil:
      t.identifier = tracks[i].child("identifier").innerText
    if tracks[i].child("creator") != nil:
      t.creator = tracks[i].child("creator").innerText
    if tracks[i].child("annotation") != nil:
      t.annotation = tracks[i].child("annotation").innerText
    if tracks[i].child("info") != nil:
      t.info = tracks[i].child("info").innerText
    if tracks[i].child("image") != nil:
      t.image = tracks[i].child("image").innerText
    if tracks[i].child("album") != nil:
      t.album = tracks[i].child("album").innerText
    if tracks[i].child("duration") != nil:
      t.duration = tracks[i].child("duration").innerText
    trackSeq[i] = t
  pl.tracks = trackSeq

  return pl


proc parseXSPF*(playlist: File): PlaylistXSPF =
  ## Parses an XSPF playlist from the given file.

  var fileContents: string = playlist.readAll()
  playlist.close()

  return parseXSPF(fileContents)


proc parsePlaylist*(playlist: string): Playlist =
  ## Determines and parses the playlist from the given string.

  # Determine the format of the playlist.
  var
    pl: Playlist = Playlist()
    chk: string = strutils.strip(playlist, leading = true)
  if unicode.toLower(chk).startsWith("[playlist]"):
    pl.format = PlaylistFormat.PLS
    pl.pls = parsePLS(playlist)
  elif chk.startsWith("#EXTM3U"):
    pl.format = PlaylistFormat.M3U
    pl.m3u = parseM3U(playlist)
  elif chk.startsWith("<xml") or chk.startsWith("<playlist>"):
    pl.format = PlaylistFormat.XSPF
    pl.xspf = parseXSPF(playlist)
  else:
    raise newException(PlaylistFormatError, "parsePlaylist(): playlist is not in a supported format")

  return pl


proc parsePlaylist*(playlist: File): Playlist =
  ## Determines and parses the playlist from the given file.

  var fileContents: string = playlist.readAll()
  playlist.close()

  return parsePlaylist(fileContents)


proc parsePlaylistSimple*(playlist: string): PlaylistSimple =
  ## Parses the playlist from the given string. Unlike ``parsePlaylist()``, this
  ## proc provides a format-neutral representation of the data to allow playlists
  ## of different formats to be used more easily. Note that this proc will give less
  ## data than the others, as some fields are not shared by all formats.

  var
    pl: PlaylistSimple = PlaylistSimple(tracks: @[])
    chk: string = strutils.strip(playlist, leading = true)
    pls: PlaylistPLS
    track: PlaylistSimpleTrack

  if unicode.toLower(chk).startsWith("[playlist]"):
    pls = parsePLS(playlist)
    pl.numberOfEntries = pls.numberOfEntries
    for i in pls.tracks:
      track = PlaylistSimpleTrack(track: i.track, file: i.file, title: i.title, length: i.length)
      pl.tracks.add(track)

  elif chk.startsWith("#EXTM3U"):
    var
      m3u: PlaylistM3U = parseM3U(playlist)
      track: PlaylistSimpleTrack
    pl.numberOfEntries = m3u.numberOfEntries
    for i in m3u.tracks:
      track = PlaylistSimpleTrack(track: i.track, file: i.file, title: i.title, length: i.length)
      pl.tracks.add(track)

  elif chk.startsWith("<xml") or chk.startsWith("<playlist"):
    var
      xspf: PlaylistXSPF = parseXSPF(playlist)
      track: PlaylistSimpleTrack
    pl.numberOfEntries = xspf.numberOfEntries
    for i in xspf.tracks:
      track = PlaylistSimpleTrack(track: i.track, file: i.location, title: i.title, length: i.duration)
      pl.tracks.add(track)

  else:
    raise newException(PlaylistFormatError, "parsePlaylistSimple(): playlist is not in a supported format")

  return pl


proc parsePlaylistSimple*(playlist: File): PlaylistSimple =
  ## Parses the playlist from the given file.

  var fileContents: string = playlist.readAll()
  playlist.close()

  return parsePlaylistSimple(fileContents)
