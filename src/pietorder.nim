import sequtils,strutils,algorithm,math,future,macros,strformat
import os,times
import pietmap



type
  Order* = enum
    ErrorOrder,Push,Pop,
    Add,Sub,Mul,
    Div,Mod,Not,
    Greater,Pointer,Switch,
    Dup,Roll,InN,
    InC,OutN,OutC,
    Wall,Nop,Terminate


proc toChar*(order:Order):char =
  return case order:
    of Push: 'P'
    of Pop: 'p'
    of Add: '+'
    of Sub: '-'
    of Mul: '*'
    of Div: '/'
    of Mod: '%'
    of Not: '!'
    of Greater: '>'
    of Pointer: '&'
    of Switch: '?'
    of Dup: 'D'
    of Roll: 'R'
    of InN: 'i'
    of InC: 'I'
    of OutN: 'o'
    of OutC: 'O'
    of Nop: '_'
    of Wall: '|'
    of ErrorOrder: 'E'
    of Terminate: '$'

proc fromChar*(c:char) : Order =
  return case c:
    of 'P' : Push
    of 'p' : Pop
    of '+' : Add
    of '-' : Sub
    of '*' : Mul
    of '/' : Div
    of '%' : Mod
    of '!' : Not
    of '>' : Greater
    of '&' : Pointer
    of '?' : Switch
    of 'D' : Dup
    of 'R' : Roll
    of 'i' : InN
    of 'I' : InC
    of 'o' : OutN
    of 'O' : OutC
    of '_' : Nop
    of '|' : Wall
    of 'E' : ErrorOrder
    of '$' : Terminate
    else : ErrorOrder

proc decideOrder*(now,next:PietColor): Order =
  if next.nwb == Black or now.nwb == Black: return Wall # 解析のためには黒のこともある
  if next.nwb == White or now.nwb == White: return Nop
  let hueDiff = (6 + (next.hue - now.hue) mod 6) mod 6
  let lightDiff = (3 + (next.light - now.light) mod 3) mod 3
  return [
    [ErrorOrder,Push,Pop],
    [Add,Sub,Mul],
    [Div,Mod,Not],
    [Greater,Pointer,Switch],
    [Dup,Roll,InN],
    [InC,OutN,OutC],
  ][hueDiff][lightDiff]
