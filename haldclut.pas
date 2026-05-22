unit haldclut;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, FPImage, IntfGraphics;

procedure ApplyHaldClut(ABitmap, AHaldClut: TBitmap);
function CloneBitmap(const ABitmap: TBitmap): TBitmap;

implementation

uses
  MTProcs;

type
  TClutColors = array[0..7] of TFPColor;

  PHaldWork = ^THaldWork;
  THaldWork = record
    SrcImg: TLazIntfImage;
    ClutImg: TLazIntfImage;
    Range: Integer;
    Width: Integer;
    Height: Integer;
    PixelCount: PtrInt;
    BlockSize: PtrInt;
  end;

function ClampByte(AValue: Integer): Byte; inline;
begin
  if AValue < 0 then Result := 0
  else if AValue > 255 then Result := 255
  else Result := AValue;
end;

function FPToByte(AValue: Word): Byte; inline;
begin
  Result := AValue shr 8;
end;

function ByteToWord(AValue: Byte): Word; inline;
begin
  Result := (Word(AValue) shl 8) or AValue;
end;

function InterpolateColor(const C1, C2: TFPColor; T: Double): TFPColor; inline;
var
  R, G, B, A: Integer;
begin
  R := Round(FPToByte(C1.Red)   * (1.0 - T) + FPToByte(C2.Red)   * T);
  G := Round(FPToByte(C1.Green) * (1.0 - T) + FPToByte(C2.Green) * T);
  B := Round(FPToByte(C1.Blue)  * (1.0 - T) + FPToByte(C2.Blue)  * T);
  A := Round(FPToByte(C1.Alpha) * (1.0 - T) + FPToByte(C2.Alpha) * T);

  Result.Red   := ByteToWord(ClampByte(R));
  Result.Green := ByteToWord(ClampByte(G));
  Result.Blue  := ByteToWord(ClampByte(B));
  Result.Alpha := ByteToWord(ClampByte(A));
end;

function TrilinearInterpolate(FracR, FracG, FracB: Double;
  const Points: TClutColors): TFPColor;
var
  C00, C01, C10, C11, C0, C1: TFPColor;
begin
  C00 := InterpolateColor(Points[0], Points[1], FracR);
  C01 := InterpolateColor(Points[2], Points[3], FracR);
  C10 := InterpolateColor(Points[4], Points[5], FracR);
  C11 := InterpolateColor(Points[6], Points[7], FracR);

  C0 := InterpolateColor(C00, C01, FracG);
  C1 := InterpolateColor(C10, C11, FracG);

  Result := InterpolateColor(C0, C1, FracB);
end;

procedure ClutPoint(X, Y, Z, Range, W, H: Integer; out PX, PY: Integer); inline;
var
  Idx: Integer;
begin
  Idx := X + Range * (Y + Range * Z);
  PX := Idx mod W;
  PY := Idx div W;
  if PY >= H then PY := H - 1;
end;

function FetchClutColors(ClutImg: TLazIntfImage; Range: Integer;
  R, G, B: Double): TClutColors;
var
  X, Y, Z, XN, YN, ZN: Integer;
  PX, PY: Integer;
begin
  X := Floor(R); Y := Floor(G); Z := Floor(B);
  XN := Min(X + 1, Range - 1);
  YN := Min(Y + 1, Range - 1);
  ZN := Min(Z + 1, Range - 1);

  ClutPoint(X,  Y,  Z,  Range, ClutImg.Width, ClutImg.Height, PX, PY); Result[0] := ClutImg.Colors[PX, PY];
  ClutPoint(XN, Y,  Z,  Range, ClutImg.Width, ClutImg.Height, PX, PY); Result[1] := ClutImg.Colors[PX, PY];
  ClutPoint(X,  YN, Z,  Range, ClutImg.Width, ClutImg.Height, PX, PY); Result[2] := ClutImg.Colors[PX, PY];
  ClutPoint(XN, YN, Z,  Range, ClutImg.Width, ClutImg.Height, PX, PY); Result[3] := ClutImg.Colors[PX, PY];
  ClutPoint(X,  Y,  ZN, Range, ClutImg.Width, ClutImg.Height, PX, PY); Result[4] := ClutImg.Colors[PX, PY];
  ClutPoint(XN, Y,  ZN, Range, ClutImg.Width, ClutImg.Height, PX, PY); Result[5] := ClutImg.Colors[PX, PY];
  ClutPoint(X,  YN, ZN, Range, ClutImg.Width, ClutImg.Height, PX, PY); Result[6] := ClutImg.Colors[PX, PY];
  ClutPoint(XN, YN, ZN, Range, ClutImg.Width, ClutImg.Height, PX, PY); Result[7] := ClutImg.Colors[PX, PY];
end;

function CloneBitmap(const ABitmap: TBitmap): TBitmap;
begin
  Result := TBitmap.Create;
  if Assigned(ABitmap) then
    Result.Assign(ABitmap);
end;

procedure ApplyHaldClutToPixel(Work: PHaldWork; PixelIndex: PtrInt); inline;
var
  X, Y: Integer;
  SrcPixel, FinalColor: TFPColor;
  R, G, B, FracR, FracG, FracB: Double;
  Points: TClutColors;
begin
  X := PixelIndex mod Work^.Width;
  Y := PixelIndex div Work^.Width;

  SrcPixel := Work^.SrcImg.Colors[X, Y];

  R := (FPToByte(SrcPixel.Red)   / 255.0) * (Work^.Range - 1);
  G := (FPToByte(SrcPixel.Green) / 255.0) * (Work^.Range - 1);
  B := (FPToByte(SrcPixel.Blue)  / 255.0) * (Work^.Range - 1);

  FracR := Frac(R);
  FracG := Frac(G);
  FracB := Frac(B);

  Points := FetchClutColors(Work^.ClutImg, Work^.Range, R, G, B);
  FinalColor := TrilinearInterpolate(FracR, FracG, FracB, Points);
  FinalColor.Alpha := SrcPixel.Alpha;
  Work^.SrcImg.Colors[X, Y] := FinalColor;
end;

procedure ApplyHaldClutBlock(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
var
  Work: PHaldWork;
  StartIndex, EndIndex, P: PtrInt;
begin
  Work := PHaldWork(Data);
  if Work = nil then Exit;

  Item.CalcBlock(Index, Work^.BlockSize, Work^.PixelCount, StartIndex, EndIndex);
  for P := StartIndex to EndIndex do
    ApplyHaldClutToPixel(Work, P);
end;

procedure ApplyHaldClut(ABitmap, AHaldClut: TBitmap);
var
  SrcImg, ClutImg: TLazIntfImage;
  Range: Integer;
  Work: THaldWork;
  BlockCount, BlockSize: PtrInt;
begin
  if (ABitmap = nil) or (AHaldClut = nil) then Exit;
  if (ABitmap.Width <= 0) or (ABitmap.Height <= 0) then Exit;
  if (AHaldClut.Width <= 0) or (AHaldClut.Height <= 0) then Exit;

  Range := Round(Power(AHaldClut.Width * AHaldClut.Height, 1.0 / 3.0));
  if Range < 2 then Exit;

  SrcImg := ABitmap.CreateIntfImage;
  try
    ClutImg := AHaldClut.CreateIntfImage;
    try
      Work.SrcImg := SrcImg;
      Work.ClutImg := ClutImg;
      Work.Range := Range;
      Work.Width := SrcImg.Width;
      Work.Height := SrcImg.Height;
      Work.PixelCount := PtrInt(SrcImg.Width) * PtrInt(SrcImg.Height);

      if Work.PixelCount <= 0 then Exit;

      ProcThreadPool.CalcBlockSize(Work.PixelCount, BlockCount, BlockSize);
      Work.BlockSize := BlockSize;

      if BlockCount <= 1 then
        ApplyHaldClutBlock(0, @Work, nil)
      else
        ProcThreadPool.DoParallel(@ApplyHaldClutBlock, 0, BlockCount - 1, @Work);

      ABitmap.LoadFromIntfImage(SrcImg);
    finally
      ClutImg.Free;
    end;
  finally
    SrcImg.Free;
  end;
end;

end.
