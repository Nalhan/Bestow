local _, CBC = ...

CBC.Pixel = {}

function CBC.Pixel:Unit()
  local scale = UIParent and UIParent:GetEffectiveScale() or 1
  if not scale or scale <= 0 then scale = 1 end
  return 1 / scale
end

function CBC.Pixel:Snap(value)
  local unit = self:Unit()
  return math.floor(value / unit + 0.5) * unit
end

function CBC.Pixel:Size(value)
  return math.max(self:Unit(), self:Snap(value))
end

function CBC.Pixel:Backdrop(frame, alpha)
  if frame.cbcBackground then return end
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(0,0,0,alpha or 0.78)
  bg:SetAllPoints(frame)
  frame.cbcBackground = bg
  frame.cbcBorders = {}
  for i=1,4 do
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetTexture(0,0,0,1)
    frame.cbcBorders[i] = edge
  end
  self:UpdateBackdrop(frame)
  CBC.pixelFrames = CBC.pixelFrames or {}
  CBC.pixelFrames[frame] = true
end

function CBC.Pixel:UpdateBackdrop(frame)
  if not frame.cbcBorders then return end
  local p = self:Unit()
  local top, bottom, left, right = unpack(frame.cbcBorders)
  top:ClearAllPoints(); top:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0); top:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0); top:SetHeight(p)
  bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",0,0); bottom:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0); bottom:SetHeight(p)
  left:ClearAllPoints(); left:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0); left:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",0,0); left:SetWidth(p)
  right:ClearAllPoints(); right:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0); right:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0); right:SetWidth(p)
end

function CBC.Pixel:Button(button, alpha)
  self:Backdrop(button, alpha or 0.55)
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture(1,1,1,0.08)
  highlight:SetAllPoints()
end

function CBC:CreateCloseButton(parent)
  local close = CreateFrame("Button", nil, parent)
  close:SetWidth(20); close:SetHeight(18); close:SetPoint("TOPRIGHT", -5, -4)
  close:SetNormalFontObject(GameFontNormalSmall); close:SetText("X")
  close:SetScript("OnClick", function() parent:Hide() end)
  self.Pixel:Button(close, 0.48)
  return close
end

function CBC:GetFontPath()
  local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
  if lsm then
    if STANDARD_TEXT_FONT then lsm:Register("font", "Friz Quadrata TT", STANDARD_TEXT_FONT) end
    return lsm:Fetch("font", self.db and self.db.font or "Friz Quadrata TT", true) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  end
  return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

function CBC:ApplyFont(fontString, size, flags)
  size, flags = size or 11, flags or ""
  fontString:SetFont(self:GetFontPath(), size, flags)
  self.fontStrings = self.fontStrings or {}
  self.fontStrings[fontString] = {size=size,flags=flags}
end

function CBC:RefreshFonts()
  local path = self:GetFontPath()
  for fontString, settings in pairs(self.fontStrings or {}) do
    fontString:SetFont(path, settings.size, settings.flags)
  end
end

function CBC:PixelRelayout()
  for frame in pairs(self.pixelFrames or {}) do self.Pixel:UpdateBackdrop(frame) end
end
