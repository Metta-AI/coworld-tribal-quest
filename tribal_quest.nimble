version     = "0.2.0"
author      = "Metta Team"
description = "Tribal Quest adventurer component for the shared Tribal Fortress Coworld."
license     = "MIT"

srcDir = "src"
bin = @["tribal_quest"]

switch("threads", "on")
switch("mm", "orc")
switch("path", "src")

requires "nim >= 2.2.10"
requires "jsony"
requires "mummy >= 0.4.7"
requires "pixie"
requires "supersnappy >= 2.1.3"
requires "ws >= 0.5.0"
