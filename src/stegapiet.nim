import common
import pietbase
import pietmap
import pietize
import curse
import makegraph
import sets
# TODO: 一筆書きの制限のせいで終了できない！
# エッジ(隣接色が同じ色の数)でマスク :: 0:変えてよい 1:それなりに 2: まあ 3:うーん 4:えー
# 色関数(近い順に並べた表を作るとわかりやすい)/ PushFlag(次Pushと確定ならばサイズ調整する価値がある)
# 次がPushを控えているからといってそのサイズじゃないといけない可能性は少ない!!
const chromMax = hueMax * lightMax
const EPS = 1e12.int

proc getInfo(self: Matrix[PietColor],x,y:int) : tuple[endPos:EightDirection[Pos],size:int] =
  # 現在位置から次の8方向を探索して返す
  let color = self[x,y]
  doAssert color >= 0 and color < chromMax
  var searched = newMatrix[bool](self.width,self.height)
  searched.point((x,y)=>false)
  var stack = newStack[Pos]()
  let here = (x.int32,y.int32)
  stack.push(here)
  var size = 1
  var endPos : EightDirection[Pos]= (here,here,here,here,here,here,here,here)
  proc updateEndPos(x,y:int32) =
    if y < endPos.upR.y : endPos.upR = (x,y)
    elif y == endPos.upR.y and x > endPos.upR.x : endPos.upR = (x,y)
    if y < endPos.upL.y : endPos.upL = (x,y)
    elif y == endPos.upL.y and x < endPos.upL.x : endPos.upL = (x,y)
    if y > endPos.downR.y : endPos.downR = (x,y)
    elif y == endPos.downR.y and x < endPos.downR.x : endPos.downR = (x,y)
    if y > endPos.downL.y : endPos.downL = (x,y)
    elif y == endPos.downL.y and x > endPos.downL.x : endPos.downL = (x,y)
    if x < endPos.leftR.x : endPos.leftR = (x,y)
    elif x == endPos.leftR.x and y < endPos.leftR.y : endPos.leftR = (x,y)
    if x < endPos.leftL.x : endPos.leftL = (x,y)
    elif x == endPos.leftL.x and y > endPos.leftL.y : endPos.leftL = (x,y)
    if x > endPos.rightR.x : endPos.rightR = (x,y)
    elif x == endPos.rightR.x and y > endPos.rightR.y : endPos.rightR = (x,y)
    if x > endPos.rightL.x : endPos.rightL = (x,y)
    elif x == endPos.rightL.x and y < endPos.rightL.y : endPos.rightL = (x,y)
  template searchNext(x2,y2:int32,op:untyped): untyped =
    block:
      let x {.inject.} = x2
      let y {.inject.} = y2
      if op and not searched[x,y] and self[x,y] == color:
        searched[x,y] = true
        size += 1
        stack.push((x,y))
  while not stack.isEmpty():
    let (x,y) = stack.pop()
    updateEndPos(x,y)
    searchNext(x-1,y  ,x >= 0)
    searchNext(x+1,y  ,x < self.width)
    searchNext(x  ,y-1,y >= 0)
    searchNext(x  ,y+1,y < self.height)
  return (endPos,size)


proc getNextPos(endPos:EightDirection[Pos],dp:DP,cc:CC) : tuple[x,y:int] =
  let (x,y) = endPos[cc,dp]
  let (dX,dY) = dp.getdXdY()
  return (x + dX,y + dY)

proc toConsole(pietMap:Matrix[PietColor]): string =
  result = ""
  for y in 0..<pietMap.height:
    for x in 0..<pietMap.width:
      let color = pietMap[x,y]
      let (r,g,b) = color.toRGB()
      proc to6(i:uint8):int = (if i == 0xff: 5 elif i == 0xc0: 3 else:1 )
      let c = case color:
        of WhiteNumber :
          getColor6(5,5,5).toBackColor() & getColor6(3,3,3).toForeColor() & '-'
        of BlackNumber :
          getColor6(0,0,0).toBackColor() & getColor6(2,2,2).toForeColor() & '*'
        else:
          getColor6(r.to6,g.to6,b.to6).toBackColor() & ' '
      result &=  c
    if y != pietMap.height - 1 : result &= "\n"
  result &= endAll & "\n"


proc `$`(orders:seq[OrderAndArgs]):string =
  result = ""
  for order in orders:
    case order.order :
    of Operation:
      if order.operation == Push : result &= "+" & order.args[0]
      else: result &= $order.operation
    else: result &= $order.order
    result &= " "

# 色差関数
proc ciede2000(l1,a1,b1,l2,a2,b2:float):float{. importc: "CIEDE2000" header: "../src/ciede2000.h".}
var ciede2000Table = newSeqWith(maxColorNumber+1, newSeqWith(maxColorNumber+1,-1))
proc distanceByCIEDE2000(a,b:PietColor) : int =
  if ciede2000Table[a][b] >= 0 : return ciede2000Table[a][b]
  proc rgb2xyz(rgb:tuple[r,g,b:uint8]): tuple[x,y,z:float] =
    # http://w3.kcua.ac.jp/~fujiwara/infosci/colorspace/colorspace2.html
    proc lin(x:uint8) : float =
      let nx = x.float / 255
      if nx > 0.04045 : pow((nx+0.055)/1.055,2.4)
      else: nx / 12.92
    let (r,g,b) = rgb
    let (lr,lg,lb) = (r.lin, g.lin, b.lin)
    return (
      lr * 0.4124 + lg * 0.3576 + lb * 0.1805,
      lr * 0.2126 + lg * 0.7152 + lb * 0.0722,
      lr * 0.0193 + lg * 0.1192 + lb * 0.9505)
  proc xyz2lab(xyz:tuple[x,y,z:float]): tuple[l,a,b:float] =
    # http://w3.kcua.ac.jp/~fujiwara/infosci/colorspace/colorspace3.html
    proc lin(x:float) : float =
      if x > 0.008856 : pow(x, 1.0/3.0)
      else: 7.787 * x + 0.1379
    let (x,y,z) = xyz
    let (nx,ny,nz) = (lin(x / 0.95047), lin(y / 1.0 ), lin(z / 1.08883))
    return (116 * ny - 16,500 * (nx - ny),200 * (ny - nz))
    # proc byCIEDE2000(lab1,lab2:tuple[l,a,b:float]) : float =
    #   proc getC(a,b:float) : float = (a*a+b*b).sqrt
    #   proc getADash(a,c:float) : float =
    #     return a * ( 1.5 - 0.5 * sqrt(pow(c,7)/(pow(c,7)+pow(25,7))))
    #   proc getDeltaAndHalf(a,b:float):tuple[d,h:float] = (b - a,(b+a) / 2)
    #   proc getH(b,ap:float):float = (360.0 + arctan2(b,ap) / (2*PI) ) mod 360.0
    #   proc getDeltaH(h1,h2:float):float =
    #     let absH = abs(h1-h2)
    #     let dH = h2 - h1
    #     return
    #       if absH < 180 : dH
    #       elif h2 < h1 : dH + 360
    #       else: dH - 360
    #   let (l1,a1,b1) = lab1
    #   let (l2,a2,b2) = lab2
    #   let (c1,c2) = (getC(a1,b1),getC(a2,b2))
    #   let (dc,hc) = getDeltaAndHalf(c1,c2)
    #   let (dl,hl) = getDeltaAndHalf(l1,l2)
    #   let (ap1,ap2) = (a1.getADash(hc),a2.getADash(hc))
    #   let (cp1,cp2) = (getC(ap1,b1),getC(ap2,b2))
    #   let (dcp,hcp) = getDeltaAndHalf(cp1,cp2)
    #   let (h1,h2) = (getH(b1,ap1),getH(b2,ap2))
    #   let dh = getDeltaH(h1,h2)
    #
    # dh
    # dH,H
    # T
    # SL
    # RT
  let (l1,a1,b1) = a.toRGB().rgb2xyz().xyz2lab()
  let (l2,a2,b2) = b.toRGB().rgb2xyz().xyz2lab()
  let distance = ciede2000(l1,a1,b1,l2,a2,b2).int * 5
  ciede2000Table[a][b] = distance
  return ciede2000Table[a][b]
proc distance(a,b:PietColor) : int = distanceByCIEDE2000(a,b)
proc showDistance() =
  var mat = newMatrix[PietColor](maxColorNumber + 1+2,maxColorNumber+1)
  for c in 0..maxColorNumber:
    mat[0,c] = c.PietColor
    mat[1,c] = -1.PietColor
    var colors = newSeq[tuple[val:int,color:PietColor]]()
    for x in 0..maxColorNumber:
      let dist = distance(x.PietColor,c.PietColor)
      colors &= (dist,x.PietColor)
    colors.sort((a,b)=>a.val-b.val)
    for i,vc in colors:
      mat[2+i,c] = vc.color
  echo mat.toConsole()
  quit()

var colorTable = newSeqWith(PietColor.high.int+1,newSeqWith(Order.high.int+1,-1))
proc getNextColor(i:int,operation:Order):int = #i.PietColor.decideNext(operation)
  if colorTable[i][operation.int] == -1:
    colorTable[i][operation.int] = i.PietColor.decideNext(operation)
  return colorTable[i][operation.int]

proc checkStegano1D(orders:seq[OrderAndArgs],base:Matrix[PietColor]) =
  if pietOrderType != TerminateAtGreater:
    quit("only TerminateAtGreater is allowed")
  # orders : inc dup ... push terminate
  doAssert orders[^1].operation == Terminate         ,"invalid"
  doAssert orders[0..^2].allIt(it.order == Operation),"invalid"
  doAssert base.height == 1
  doAssert base.width >= orders.len()

proc stegano1D*(orders:seq[OrderAndArgs],base:Matrix[PietColor]) =
  checkStegano1D(orders,base)
  # result = newMatrix[PietColor](base.width,1)
  # https://photos.google.com/photo/AF1QipMlNFgMkP-_2AtsRZcYbPV3xkBjU0q8bKxql9p3?hl=ja
  # 有彩色 + 白 (黒は使用しない)
  type DPKey = tuple[color,nop,ord,fund:int]  # [color][Nop][Order][Fund]
  type DPVal = tuple[val:int,preKey:DPKey] # Σ,前のやつ
  const initDPKey :DPKey = (0,0,0,0)
  const maxFund = 10
  var dp = newSeqWith(chromMax + 1,newSeqWith(base.width,newSeqWith(base.width,newSeq[DPVal]())))
  proc `[]` (self:var seq[seq[seq[seq[DPVal]]]],key:DPKey) : DPVal =
    doAssert self[key.color][key.nop][key.ord].len() > key.fund
    self[key.color][key.nop][key.ord][key.fund]
  block: # 最初は白以外
    let color = base[0,0]
    for i in 0..<chromMax:
      dp[i][0][0] = @[(distance(color,i.PietColor),initDPKey)]
  for progress in 0..<(base.width-1):
    # if progress mod 10 == 0 : echo progress
    let baseColor = base[progress+1,0]
    proc diff(color:int) : int = distance(baseColor,color.PietColor)
    proc update(pre,next:DPKey) =
      if dp[pre.color][pre.nop][pre.ord].len() == 0 : return
      if dp[pre].val >= EPS: return
      let nextDp = dp[next.color][next.nop][next.ord]
      let nextVal = dp[pre].val + diff(next.color)
      let dpVal = (nextVal,pre)
      if nextDp.len() <= next.fund :
        if nextDp.len() == next.fund:
          dp[next.color][next.nop][next.ord] &= dpVal
        else:
          for i in 0..<(next.fund-nextDp.len()): # WARN
            dp[next.color][next.nop][next.ord] &= (EPS,initDPKey)
          dp[next.color][next.nop][next.ord] &= dpVal
      elif nextVal >= dp[next].val: return
      else: dp[next.color][next.nop][next.ord][next.fund] = dpVal
    for nop in 0..progress:
      let ord = progress - nop
      # もう命令を全て終えた
      if ord >= orders.len(): continue
      let order = orders[ord]
      proc here(color:int): seq[DPVal] = dp[color][nop][ord]
      proc d(color,dNop,dOrd,f:int) : DPKey = (color,nop+dNop,ord+dOrd,f)
      # 命令を進めた
      for i in 0..<chromMax:
        update(d(i,0,0,0),d(i.getNextColor(order.operation),0,1,0))
      # Nop (白 -> 白)
      for f in 0..<here(chromMax).len():
        update(d(chromMax,0,0,f),d(chromMax,1,0,f))
      # Nop ([]->白)
      for i in 0..<chromMax:
        for f in 0..<here(i).len():
          update(d(i,0,0,f),d(chromMax,1,0,f))
      # Nop (白->[])
      for f in 0..<here(chromMax).len():
        for i in 0..<chromMax:
          update(d(chromMax,0,0,f),d(i,1,0,f))
      # Fund
      for i in 0..<chromMax:
        if false:
          # そんなわけないが任意の色に行けるとする場合(これはめちゃくちゃうまく行かなければおかしい)
          for j in 0..<chromMax:
            for f in 0..<here(i).len():
              update(d(i,0,0,f),d(j,1,0,f+1))
            for f in 1..<here(i).len():
              update(d(i,0,0,f),d(j,1,0,f-1))
        else:
          # 普通
          if ord+1 < orders.len() and orders[ord+1].operation != Push:
            update(d(i,0,0,0),d(i,1,0,0)) # 次Pushがわかってるのに増やすことはできない
          for f in 0..<min(here(i).len(),maxFund-1):
            update(d(i,0,0,f),d(i.getNextColor(Push),1,0,f+1))
          for f in 1..<min(here(i).len(),maxFund-1):
            update(d(i,0,0,f),d(i,1,0,f))
            update(d(i,0,0,f),d(i.getNextColor(Pop),1,0,f-1))
            update(d(i,0,0,f),d(i.getNextColor(Not),1,0,f))
            update(d(i,0,0,f),d(i.getNextColor(Dup),1,0,f+1))
          for f in 2..<min(here(i).len(),maxFund-1):
            update(d(i,0,0,f),d(i.getNextColor(Add),1,0,f-1))
            update(d(i,0,0,f),d(i.getNextColor(Sub),1,0,f-1))
            update(d(i,0,0,f),d(i.getNextColor(Mul),1,0,f-1))
            update(d(i,0,0,f),d(i.getNextColor(Div),1,0,f-1))
            update(d(i,0,0,f),d(i.getNextColor(Mod),1,0,f-1))
  proc showPath(startKey:DPKey) =
    var key = startKey
    var colors = newSeq[int]()
    while not(key.nop == 0 and key.ord == 0 and key.fund == 0):
      colors &= key.color
      let nowDp = dp[key]
      key = nowDp.preKey
    colors &= key.color
    colors.reverse()
    var echoMat = newMatrix[PietColor](colors.len(),1)
    for i,color in colors: echoMat[i,0] = color.PietColor
    echo dp[startKey].val,":",colors.len()
    echo echoMat.toConsole()
    echo base.toConsole()
    echo echoMat.newGraph()[0].orderAndSizes.mapIt(it.order)
    echo orders
  var mins = newSeq[DPKey]()
  for progress in 0..<base.width:
    for nop in 0..progress:
      let ord = progress - nop
      if ord < orders.len(): continue
      let minIndex = toSeq(0..chromMax).mapIt(
        if dp[it][nop][ord].len() == 0 : EPS else:dp[it][nop][ord][0].val
        ).argmin()
      let minVal = dp[minIndex][nop][ord]
      if minVal.len() == 0 or minVal[0].val == EPS : continue
      mins &= (minIndex,nop,ord,0)
  for m in mins.sorted((a,b)=>dp[a].val - dp[b].val)[0..<min(1,mins.len())]:
    showPath(m)

proc quasiStegano1D*(orders:seq[OrderAndArgs],base:Matrix[PietColor]) =
  # ビームサーチでそれなりによいものを探す
  checkStegano1D(orders,base)
  const maxFrontierNum = 100
  # index == ord | N個の [PietMat,先頭{Color,DP,CC,Fund}]
  type Val = tuple[val:int,mat:Matrix[PietColor],x,y:int,dp:DP,cc:CC,fund:int]
  var fronts = newSeqWith(1,newSeq[Val]())
  block: # 最初は白以外
    let color = base[0,0]
    for i in 0..<chromMax:
      var initMat = newMatrix[PietColor](base.width,base.height)
      initMat.point((x,y) => -1)
      initMat[0,0] = i.PietColor
      fronts[0] &= (distance(color,i.PietColor),initMat,0,0,newDP(),newCC(),0)
  for progress in 0..<(base.width-1):
    var nexts = newSeqWith(min(fronts.len(),orders.len())+1,newSeq[Val]())
    for ord in 0..<fronts.len():
      let front = fronts[ord]
      if ord == orders.len():
        for f in front: nexts[ord] &= f
        continue
      let order = orders[ord]
      proc push(f:Val,nextColor,dx,dy,dOrd,dFund:int,dp:DP,cc:CC) =
        var next : Val = (f.val,f.mat.deepCopy(),f.x + dx,f.y + dy,dp,cc,f.fund+dFund)
        next.mat[next.x,next.y] = nextColor.PietColor
        next.val += distance(nextColor.PietColor,base[next.x,next.y])
        nexts[ord+dOrd] &= next
      proc pushAs1D(f:Val,nextColor,dOrd,dFund:int) =
        f.push(nextColor,1,0,dOrd,dFund,f.dp,f.cc)
      for f in front:
        let hereColor = f.mat[f.x,f.y]
        if f.fund == 0 and hereColor != chromMax: # 命令を進めた
          f.pushAs1D(hereColor.getNextColor(order.operation),1,0)
        # Nop (* -> 白)
        f.pushAs1D(chromMax,0,0)
        if hereColor == chromMax: # (白 -> *)
          for i in 0..<chromMax: f.pushAs1D(i,0,0)
        else: # Fund(白では詰めない)
          f.pushAs1D(hereColor.getNextColor(Push),0,1)
          if ord+1 < orders.len() and orders[ord+1].operation != Push:
            f.pushAs1D(hereColor,0,0) # WARN: 次がPushというせいでNopなどもできない!!
          if f.fund > 0:
            f.pushAs1D(hereColor.getNextColor(Pop),0,-1)
            f.pushAs1D(hereColor.getNextColor(Not),0,0)
            f.pushAs1D(hereColor.getNextColor(Dup),0,1)
          if f.fund > 1:
            f.pushAs1D(hereColor.getNextColor(Add),0,-1)
            f.pushAs1D(hereColor.getNextColor(Sub),0,-1)
            f.pushAs1D(hereColor.getNextColor(Mul),0,-1)
            f.pushAs1D(hereColor.getNextColor(Div),0,-1)
            f.pushAs1D(hereColor.getNextColor(Mod),0,-1)
    fronts = nexts.mapIt(it.sorted((a,b)=>a.val-b.val)[0..min(it.len(),maxFrontierNum)-1])
  block:
    let front = fronts[^1]
    echo "->{front[0].val}".fmt()
    echo front[0].mat.toConsole()
    echo base.toConsole()
    echo front[0].mat.newGraph()[0].orderAndSizes.mapIt(it.order)
    echo orders

proc quasiStegano2D*(orders:seq[OrderAndArgs],base:Matrix[PietColor],maxFrontierNum :int=500) :Matrix[PietColor]=
  const maxEmbedColor = 20
  type Val = tuple[val:int,mat:Matrix[PietColor],x,y:int,dp:DP,cc:CC,fund:Stack[int]]
  proc isIn(x,y:int):bool = x >= 0 and y >= 0 and x < base.width and y < base.height
  proc updateVal(val:var int,x,y:int,color:PietColor) =
    val += distance(color,base[x,y]) + 1
  proc updateMat(mat:var Matrix[PietColor],x,y:int,color:PietColor) =
    mat[x,y] = color
  proc update(mat:var Matrix[PietColor],val:var int,x,y:int,color:PietColor) =
    if mat[x,y] == color: return
    mat.updateMat(x,y,color)
    val.updateVal(x,y,color)
  proc isDecided(mat:Matrix[PietColor],x,y:int) : bool = mat[x,y] >= 0
  proc isChromatic(mat:Matrix[PietColor],x,y:int) : bool = mat[x,y] >= 0 and mat[x,y] < chromMax
  proc checkAdjast(mat:Matrix[PietColor],color:PietColor,x,y:int) : bool =
    for dxdy in [(0,1),(0,-1),(1,0),(-1,0)]:
      let (dx,dy) = dxdy
      let (nx,ny) = (x + dx,y + dy)
      if not isIn(nx,ny) : continue
      if mat[nx,ny] == color : return true
    return false
  proc checkNextIsNotDecided(mat:Matrix[PietColor],x,y:int,dp:DP,cc:CC) : bool =
    let (cX,cY) = mat.getInfo(x,y).endPos.getNextPos(dp,cc)
    if not isIn(cX,cY) or mat.isDecided(cX,cY) : return false
    return true
  type EmbedColorType = tuple[mat:Matrix[PietColor],val:int]
  var stack = newStack[tuple[x,y,val:int,mat:Matrix[PietColor],size:int]]() # プーリング
  proc embedColor(startMat:Matrix[PietColor],startVal,startX,startY:int,color:PietColor,allowScore:int,allowBlockSize:int): seq[EmbedColorType] =
    # 未確定の場所を埋めれるだけ埋めてゆく(ただし上位スコアmaxEmbedColorまで)
    # ただし,埋めれば埋めるほど当然損なので,最大でもmaxEmbedColorマスサイズにしかならない
    doAssert color < chromMax
    doAssert stack.len() == 0
    # q.top()が一番雑魚になる
    var q = newBinaryHeap[EmbedColorType](proc(x,y:EmbedColorType): int = y.val - x.val)
    template checkAndPush(x,y,val,mat,size) =
      if isIn(x,y) and
          (allowBlockSize <= 0 or size <= allowBlockSize) and
          not mat.isDecided(x,y) and
          not startMat.checkAdjast(color,x,y) :
        stack.push((x,y,val,mat,size))
    checkAndPush(startX,startY,startVal,startMat,1)
    var table = initSet[Matrix[PietColor]]()
    while not stack.isEmpty():
      # WARN: 一筆書きできるようにしか配置できない！
      let (x,y,val,mat,size) = stack.pop()
      var newVal = val
      newVal.updateVal(x,y,color)
      if allowScore <= newVal : continue
      if q.len() > maxEmbedColor: # 多すぎるときは一番雑魚を省く
        if q.top().val <= newVal : continue
        table.excl(q.pop().mat)
      var newMat = mat.deepCopy()
      newMat.updateMat(x,y,color)
      if newMat in table : continue
      if allowBlockSize <= 0 or size == allowBlockSize :
        # if allowBlockSize > 0 : echo size
        q.push((newMat,newVal))
        table.incl(newMat)
      checkAndPush(x+1,y,newVal,newMat,size+1)
      checkAndPush(x-1,y,newVal,newMat,size+1)
      checkAndPush(x,y+1,newVal,newMat,size+1)
      checkAndPush(x,y-1,newVal,newMat,size+1)
    result = @[]
    while q.len() > 0: result &= q.pop()
  proc tryAllDPCC(mat:Matrix[PietColor],eightDirection:EightDirection[Pos],startDP:DP,startCC:CC) : tuple[ok:bool,dp:DP,cc:CC]=
    # 次に壁ではない場所にいけるなら ok
    var dp = startDP
    var cc = startCC
    for i in 0..<8:
      let (nX,nY) = eightDirection.getNextPos(dp,cc)
      if not isIn(nX,nY) or mat[nX,nY] == BlackNumber:
        if i mod 2 == 0 : cc.toggle()
        else: dp.toggle(1)
        continue
      return (true,dp,cc)
    return (false,dp,cc)

  var fronts = newSeqWith(1,newSeq[Val]())
  var completedMin = EPS
  block: # 最初は白以外
    for i in 0..<chromMax:
      var initMat = newMatrix[PietColor](base.width,base.height)
      initMat.point((x,y) => -1)
      let nextIsPush = if orders[0].operation == Push: orders[0].args[0].parseInt() else: -1
      let choises = initMat.embedColor(0,0,0,i.PietColor,EPS,nextIsPush)
      for choise in choises:
        fronts[0] &= (choise.val,choise.mat,0,0,newDP(),newCC(),newStack[int]())
      fronts = fronts.mapIt(it.sorted((a,b)=>a.val-b.val)[0..min(it.len(),maxFrontierNum)-1])
  for progress in 0..<(base.width * base.height):
    var nexts = newSeqWith( # top()が一番雑魚になる
        min(fronts.len(),orders.len())+1,
        newBinaryHeap[Val](proc(x,y:Val): int = y.val - x.val))
    proc storedWorstVal(ord:int):int =
      if nexts[ord].len() < maxFrontierNum : return min(EPS,completedMin)
      if nexts[ord].len() == 0 : return min(EPS,completedMin)
      return min(nexts[ord].top().val,completedMin)
    proc store(ord:int,val:Val) =
      if storedWorstVal(ord) <= val.val : return
      nexts[ord].push(val)
      if nexts[ord].len() > maxFrontierNum :
        discard nexts[ord].pop()
    for ord in 0..<fronts.len():
      let front = fronts[ord]
      if ord == orders.len():
        for f in front:
          completedMin .min= f.val
          nexts[ord].push(f)
        continue
      let order = orders[ord]
      for f in front:
        let hereColor = f.mat[f.x,f.y]
        if hereColor >= chromMax : continue # 簡単のために白は経由しない
        let endPos = f.mat.getInfo(f.x,f.y).endPos
        proc decide(dOrd:int,color:PietColor,allowBlockSize:int,callback:proc(_:var Val):bool) =
          let (ok,dp,cc) = f.mat.tryAllDPCC(endPos,f.dp,f.cc)
          if not ok : return
          let (nX,nY) = endPos.getNextPos(dp,cc)
          let nOrd = ord+dOrd
          if f.mat.isDecided(nX,nY) : # このままいけそうなら交差してみます
            if f.mat[nX,nY] != color : return
            if not f.mat.checkNextIsNotDecided(nX,nY,dp,cc): return
            var next : Val = (f.val,f.mat.deepCopy(),nX,nY,dp,cc,f.fund.deepCopy())
            if not next.callback():return
            store(nOrd,next)
            return
          # 次がPushなら Push 1 なので 1マスだけなのに注意
          let choises = f.mat.embedColor(f.val,nX,nY,color,storedWorstVal(nOrd),allowBlockSize)
          for choise in choises:
            var next : Val = (choise.val,choise.mat,nX,nY,dp,cc,f.fund.deepCopy())
            if not next.callback():continue
            store(nOrd,next)
          return

        if f.fund.len() == 0 and order.operation != Terminate: # 命令を進められるのは fund == 0 のみ
          let nextIsPush = if ord + 1 < orders.len() and orders[ord+1].operation == Push: orders[ord+1].args[0].parseInt() else: -1
          let nextColor = hereColor.getNextColor(order.operation)
          decide(1,nextColor.PietColor,nextIsPush,proc(_:var Val):bool=true)
        if order.operation == Terminate:
          (proc =
            var dp = f.dp
            var cc = f.cc
            var mat = f.mat.deepCopy()
            var val = f.val
            for i in 0..<2: # TODO: 大嘘
              let (bX,bY) = endPos.getNextPos(dp,cc)
              if isIn(bX,bY):
                # 黒をおかなければならない
                if mat[bX,bY] != BlackNumber: return
                if not mat.isDecided(bX,bY):
                  mat.update(val,bX,bY,BlackNumber)
              if i mod 2 == 0 : cc.toggle()
              else: dp.toggle(1)
            # 全方向巡りできた
            store(ord+1,(val,mat,f.x,f.y,dp,cc,f.fund.deepCopy()))
          )()
        (proc = # 次の行き先に1マスだけ黒ポチー
          let (bX,bY) = endPos.getNextPos(f.dp,f.cc)
          if not isIn(bX,bY): return
          # 既に黒が置かれているならわざわざ置く必要がない
          if f.mat.isDecided(bX,bY) : return
          var next : Val = (f.val,f.mat.deepCopy(),f.x,f.y,f.dp,f.cc,f.fund.deepCopy())
          next.mat.update(next.val,bX,bY,BlackNumber)
          store(ord,next)
        )()
        (proc = # 白を使うNop
          # 現仕様ではPiet08/KMCPietどちらでも動く！
          # WARN: x - - | # 壁で反射みたいなこともできるよねー
          # x - - - y (-の数N * 次の色C)
          let (ok,dp,cc) = f.mat.tryAllDPCC(endPos,f.dp,f.cc)
          if not ok : return
          let (dx,dy) = dp.getdXdY()
          var (x,y) = endPos.getNextPos(dp,cc)
          for i in 1..max(base.width,base.height):
            let (cx,cy) = (x+dx*i,y+dy*i)
            # 流石にはみ出したら終了
            if not isIn(x,y) : break
            if not isIn(cx,cy) : break
            # 伸ばしている途中でいい感じになる可能性があるので continue
            # 全て道中は白色にできないといけない
            if (proc ():bool =
              for j in 0..<i:
                let (jx,jy) = (x+dx*j,y+dy*j)
                if f.mat[jx,jy] != WhiteNumber and f.mat.isDecided(jx,jy) : return true
              return false
              )() : continue
            proc toWhites(f:var Val) =
              for j in 0..<i:
                let (jx,jy) = (x+dx*j,y+dy*j)
                f.mat.update(f.val,jx,jy,WhiteNumber)

            if f.mat.isDecided(cx,cy):
              # 交差するが行けるときはいく
              if not f.mat.isChromatic(cx,cy) : continue
              if not f.mat.checkNextIsNotDecided(cx,cy,dp,cc) : continue
              var next : Val = (f.val,f.mat.deepCopy(),cx,cy,dp,cc,f.fund.deepCopy())
              next.toWhites()
              store(ord,next)
              continue
            # 白の次にマス
            var next : Val = (f.val,f.mat.deepCopy(),cx,cy,dp,cc,f.fund)
            next.toWhites()
            for c in 0..<chromMax:
              if next.mat.checkAdjast(c.PietColor,cx,cy) : continue
              let nextIsPush = if ord < orders.len() and orders[ord].operation == Push: orders[ord].args[0].parseInt() else: -1
              let choises = next.mat.embedColor(next.val,cx,cy,c.PietColor,storedWorstVal(ord),nextIsPush)
              for choise in choises:
                store(ord,(choise.val,choise.mat,cx,cy,dp,cc,next.fund.deepCopy()))
        )()
        # fund
        decide(0,hereColor.getNextColor(Push).PietColor,-1,
            proc(v:var Val) :bool=
              v.fund.push(v.mat.getInfo(v.x,v.y).size)
              return true )
        if f.fund.len() > 0 :
          decide(0,hereColor.getNextColor(Pop).PietColor,-1,
              proc(v:var Val) :bool=
                discard v.fund.pop()
                return true)
          decide(0,hereColor.getNextColor(Switch).PietColor,-1,
            proc(v:var Val) :bool=
              if v.fund.pop() mod 2 == 1 : v.cc.toggle()
              return true)
          decide(0,hereColor.getNextColor(Pointer).PietColor,-1,
            proc(v:var Val) :bool=
              v.dp.toggle(v.fund.pop())
              return true)
          decide(0,hereColor.getNextColor(Not).PietColor,-1,
              proc(v:var Val) :bool=
                v.fund.push(if v.fund.pop() == 0: 1 else: 0)
                return true)
          decide(0,hereColor.getNextColor(Dup).PietColor,-1,
              proc(v:var Val) :bool=
                v.fund.push(v.fund.top())
                return true)
        if f.fund.len() > 1:
          decide(0,hereColor.getNextColor(Add).PietColor,-1,
            proc(v:var Val) :bool=
                let top = v.fund.pop()
                let next = v.fund.pop()
                v.fund.push(next + top)
                return true)
          decide(0,hereColor.getNextColor(Sub).PietColor,-1,
            proc(v:var Val) :bool=
                let top = v.fund.pop()
                let next = v.fund.pop()
                v.fund.push(next - top)
                return true)
          decide(0,hereColor.getNextColor(Mul).PietColor,-1,
            proc(v:var Val) :bool=
                let top = v.fund.pop()
                let next = v.fund.pop()
                v.fund.push(next * top)
                return true)
          decide(0,hereColor.getNextColor(Div).PietColor,-1,
            proc(v:var Val) :bool=
                let top = v.fund.pop()
                let next = v.fund.pop()
                if top == 0 : return false
                v.fund.push(next div top)
                return true)
          decide(0,hereColor.getNextColor(Mod).PietColor,-1,
            proc(v:var Val) :bool=
                let top = v.fund.pop()
                let next = v.fund.pop()
                if top == 0 : return false
                v.fund.push(next mod top)
                return true)
          decide(0,hereColor.getNextColor(Greater).PietColor,-1,
            proc(v:var Val) :bool=
                let top = v.fund.pop()
                let next = v.fund.pop()
                v.fund.push(if next > top : 1 else:0)
                return true)

    let nextItems = toSeq(0..<nexts.len()).mapIt(nexts[it].items())
    if fronts[^1].len() > 0 :
      # 最後のプロセス省略
      if progress > 0 and nextItems[0..^2].allIt(it.len() == 0) : break
      # echo nextItems.mapIt(it.len())
      # echo nextItems.mapIt(it.mapIt(it.val)).filterIt(it.len() > 0).mapIt([it.max(),it.min()])
      echo fronts[^1][0].mat.toConsole(),fronts[^1][0].val,"\n"
      # echo fronts[^1][0].mat.newGraph().mapIt(it.orderAndSizes.mapIt(it.order))
      # stdout.write progress;stdout.flushFile
    fronts = nextItems.mapIt(it.sorted((a,b)=>a.val-b.val)[0..min(it.len(),maxFrontierNum)-1])
  block: # 成果
    proc embedNotdecided(self:var Matrix[PietColor]) : int =
      let initalMatrix = self.deepCopy()
      for x in 0..<self.width:
        for y in 0..<self.height:
          if self.isDecided(x,y): continue
          let color = base[x,y]
          if color >= chromMax or not initalMatrix.checkAdjast(color,x,y):
            self[x,y] = color
      result = 0
      for x in 0..<self.width:
        for y in 0..<self.height:
          if self.isDecided(x,y): continue
          var minVal = EPS
          for c in 0..<chromMax:
            if initalMatrix.checkAdjast(c.PietColor,x,y) : continue
            let dist = distance(c.PietColor,base[x,y])
            if dist < minVal:
              self[x,y] = c.PietColor
              minVal = dist
          result += minVal
    proc findEmbeddedMinIndex():int =
      var minIndex = 0
      var minVal = EPS
      for i,front in fronts[^1]:
        var mat = front.mat.deepCopy()
        var val = front.val
        val += mat.embedNotdecided()
        if minVal < val : continue
        minIndex = i
        minVal = val
      return minIndex
    doAssert fronts[^1].len() > 0
    result = fronts[^1][findEmbeddedMinIndex()].mat
    echo "before:result :\n",result.toConsole()
    discard result.embedNotdecided()
    echo "result :\n",result.toConsole()
    echo "base   :\n",base.toConsole()
    echo result.newGraph().mapIt(it.orderAndSizes.mapIt(it.order))
    echo orders



proc makeRandomOrders(length:int):seq[OrderAndArgs] =
  randomize()
  proc getValidOrders():seq[Order] =
    result = @[]
    for oo in orderBlock:
      for o in oo:
        if o notin [ErrorOrder,Terminate,Pointer,Switch] :
          result &= o
  result = @[]
  let orderlist = getValidOrders()
  for _ in 0..<length:
    let order = orderlist[rand(orderlist.len()-1)]
    let args = if order == Push : @["1"] else: @[]
    result &= (Operation,order,args)
  result &= (MoveTerminate,Terminate,@[])

proc makeRandomPietColorMatrix*(width,height:int) : Matrix[PietColor] =
  randomize()
  result = newMatrix[PietColor](width,height)
  for x in 0..<width:
    for y in 0..<height:
      result[x,y] = rand(maxColorNumber).PietColor

proc makeLocalRandomPietColorMatrix*(width,height:int) : Matrix[PietColor] =
  randomize()
  result = newMatrix[PietColor](width,height)
  const same = 5
  for x in 0..<width:
    for y in 0..<height:
      result[x,y] = rand(maxColorNumber).PietColor
      if rand(1) == 0:
        if rand(10) > same and x > 0:
          result[x,y] = result[x-1,y]
        if rand(10) > same and y > 0:
          result[x,y] = result[x,y-1]
      else:
        if rand(10) > same and y > 0:
          result[x,y] = result[x,y-1]
        if rand(10) > same and x > 0:
          result[x,y] = result[x-1,y]

if isMainModule:

  if false:
    let orders = makeRandomOrders(20)
    let baseImg = makeRandomPietColorMatrix(64,1)
    stegano1D(orders,baseImg)
    quasiStegano1D(orders,baseImg)
  if false:
    let orders = makeRandomOrders(20)
    let baseImg = makeLocalRandomPietColorMatrix(12,12)
    echo baseImg.toConsole()
    discard quasiStegano2D(orders,baseImg,400).toConsole()
  if commandLineParams().len() > 0:
    let baseImg = commandLineParams()[0].newPietMap().pietColorMap
    proc getOrders():seq[OrderAndArgs] =
      result = @[]
      proc d(ord:Order,n:int = -1):tuple[ord:Order,arg:seq[string]] =
        if n <= 0 and ord != Push : return (ord,@[])
        else: return (ord,@[$n])
      let orders = @[
        # 80 73 69 84
        d(Push,3),d(Dup),d(Mul),d(Dup),d(Mul),d(Push,1),d(Sub),d(Dup),d(OutC),
        d(Push,3),d(Dup),d(Push,1),d(Add),d(Add),d(Sub),d(Dup),d(OutC),
        d(Push,2),d(Dup),d(Add),d(Sub),d(Dup),d(OutC),
        d(Push,3),d(Dup),d(Push,2),d(Add),d(Mul),d(Add),d(OutC)
      ]
      for oa in orders:
        let (order,args) = oa
        result &= (Operation,order,args)
      result &= (MoveTerminate,Terminate,@[])
    let orders = getOrders()
    # let orders = makeRandomOrders((baseImg.width.float * baseImg.height.float * 0.1).int)
    echo orders
    echo baseImg.toConsole()
    let stegano = quasiStegano2D(orders,baseImg,1000)
    stegano.save("./piet.png")


  # baseImg.save()
  # stegano.save()