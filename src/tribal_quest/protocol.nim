const
  DefaultHost* = "localhost"
  DefaultPort* = 8080

  ButtonUp* = 1'u8 shl 0
  ButtonDown* = 1'u8 shl 1
  ButtonLeft* = 1'u8 shl 2
  ButtonRight* = 1'u8 shl 3
  ButtonSelect* = 1'u8 shl 4
  ButtonA* = 1'u8 shl 5
  ButtonB* = 1'u8 shl 6

proc blobFromBytes*(bytes: openArray[uint8]): string =
  result = newString(bytes.len)
  for i, value in bytes:
    result[i] = char(value)

proc spriteInputPacket*(mask: uint8): string =
  result = newString(2)
  result[0] = char(0x84'u8)
  result[1] = char(mask and 0x7f'u8)
