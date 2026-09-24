proc chooseAdventurerMask*(tick, stagnantFrames: int): uint8 =
  let phase = ((tick div 12) + (stagnantFrames div 3)) mod 6
  case phase
  of 0, 1:
    result = 8'u8
  of 2:
    result = 2'u8
  of 3, 4:
    result = 4'u8
  else:
    result = 1'u8

  if tick mod 9 == 0:
    result = result or 32'u8
  if tick mod 37 == 0:
    result = result or 64'u8
