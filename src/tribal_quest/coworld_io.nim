import std/[httpclient, httpcore, json, os, strutils, uri]

const CoworldUserAgent = "coworld-tribal-quest/0.2"

proc filePath(value: string): string =
  let parsed = parseUri(value)
  decodeUrl(parsed.path)

proc readCoworldData*(value, source: string): string =
  ## Reads hosted configuration data. Output artifact URIs deliberately use a
  ## separate writer below because HTTP artifact methods are not GET.
  if value.len == 0:
    return ""
  if value.startsWith("http://") or value.startsWith("https://"):
    var client = newHttpClient(
      userAgent = CoworldUserAgent,
      timeout = 30_000
    )
    try:
      return client.getContent(value)
    finally:
      client.close()
  if value.startsWith("file://"):
    return readFile(value.filePath())
  if "://" in value:
    raise newException(ValueError, "unsupported URI from " & source & ": " & value)
  readFile(value)

proc artifactHttpMethod*(envName: string): HttpMethod =
  let value = getEnv(envName, "PUT").strip().toUpperAscii()
  case value
  of "POST": HttpPost
  of "PUT": HttpPut
  else:
    raise newException(ValueError, envName & " must be POST or PUT")

proc writeCoworldJson*(value: string, node: JsonNode, methodEnvName: string) =
  if value.len == 0:
    return
  let body = $node
  if value.startsWith("http://") or value.startsWith("https://"):
    var
      client = newHttpClient(
        userAgent = CoworldUserAgent,
        timeout = 60_000
      )
      headers = newHttpHeaders()
    headers["Content-Type"] = "application/json"
    try:
      let response = client.request(
        value,
        httpMethod = artifactHttpMethod(methodEnvName),
        body = body,
        headers = headers
      )
      if response.code.int < 200 or response.code.int >= 300:
        raise newException(
          IOError,
          "artifact upload failed with HTTP " & $response.code.int
        )
      return
    finally:
      client.close()

  let path =
    if value.startsWith("file://"): value.filePath()
    elif "://" in value:
      raise newException(ValueError, "unsupported artifact URI: " & value)
    else: value
  let parent = path.parentDir()
  if parent.len > 0 and not dirExists(parent):
    createDir(parent)
  writeFile(path, body)
