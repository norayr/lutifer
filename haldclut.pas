unit haldclut;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, FPImage;

procedure ApplyHaldClut(AImage, AHaldClut: TFPCustomImage);
function HaldClutRange(AHaldClut: TFPCustomImage): Integer;
function IsProbablyHaldClut(AHaldClut: TFPCustomImage; out Range: Integer): Boolean;

implementation

uses
  MTProcs;

type
  TFastPixel = packed record
    R, G, B, A: Byte;
  end;

  TFastPixelArray = array of TFastPixel;

  PHaldWork = ^THaldWork;
  THaldWork = record
    Pixels: ^TFastPixelArray;
    Lut: ^TFastPixelArray;
    Range: Integer;
    PixelCount: PtrInt;
    BlockSize: PtrInt;
  end;

function ByteToWord(AValue: Byte): Word; inline;
begin
  Result := (Word(AValue) shl 8) or AValue;
end;

function FPToByte(AValue: Word): Byte; inline;
begin
  Result := AValue shr 8;
end;

function FPColorToFast(const C: TFPColor): TFastPixel; inline;
begin
  Result.R := FPToByte(C.Red);
  Result.G := FPToByte(C.Green);
  Result.B := FPToByte(C.Blue);
  Result.A := FPToByte(C.Alpha);
end;

function FastToFPColor(const P: TFastPixel): TFPColor; inline;
begin
  Result.Red := ByteToWord(P.R);
  Result.Green := ByteToWord(P.G);
  Result.Blue := ByteToWord(P.B);
  Result.Alpha := ByteToWord(P.A);
end;

function LerpByte(A, B, T: Integer): Byte; inline;
begin
  // T is 0..255. This is integer linear interpolation with rounding.
  Result := (A * (255 - T) + B * T + 127) div 255;
end;

function LerpPixel(const A, B: TFastPixel; T: Integer): TFastPixel; inline;
begin
  Result.R := LerpByte(A.R, B.R, T);
  Result.G := LerpByte(A.G, B.G, T);
  Result.B := LerpByte(A.B, B.B, T);
  Result.A := LerpByte(A.A, B.A, T);
end;

function TrilinearInteger(const C000, C100, C010, C110,
  C001, C101, C011, C111: TFastPixel; FR, FG, FB: Integer): TFastPixel; inline;
var
  C00, C01, C10, C11, C0, C1: TFastPixel;
begin
  C00 := LerpPixel(C000, C100, FR);
  C01 := LerpPixel(C010, C110, FR);
  C10 := LerpPixel(C001, C101, FR);
  C11 := LerpPixel(C011, C111, FR);
  C0 := LerpPixel(C00, C01, FG);
  C1 := LerpPixel(C10, C11, FG);
  Result := LerpPixel(C0, C1, FB);
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

function HaldClutRange(AHaldClut: TFPCustomImage): Integer;
var
  Pixels: Double;
begin
  Result := 0;
  if (AHaldClut = nil) or (AHaldClut.Width <= 0) or (AHaldClut.Height <= 0) then
    Exit;
  Pixels := Double(AHaldClut.Width) * Double(AHaldClut.Height);
  Result := Round(Power(Pixels, 1.0 / 3.0));
end;

function IsProbablyHaldClut(AHaldClut: TFPCustomImage; out Range: Integer): Boolean;
begin
  Range := HaldClutRange(AHaldClut);
  Result :=
    (Range >= 2) and
    (Int64(Range) * Int64(Range) * Int64(Range) =
      Int64(AHaldClut.Width) * Int64(AHaldClut.Height));
end;

procedure LoadImageToFast(AImage: TFPCustomImage; out Pixels: TFastPixelArray);
var
  X, Y, W, H: Integer;
  I: PtrInt;
begin
  W := AImage.Width;
  H := AImage.Height;
  SetLength(Pixels, PtrInt(W) * PtrInt(H));
  I := 0;
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      Pixels[I] := FPColorToFast(AImage.Colors[X, Y]);
      Inc(I);
    end;
end;

procedure StoreFastToImage(const Pixels: TFastPixelArray; AImage: TFPCustomImage);
var
  X, Y, W, H: Integer;
  I: PtrInt;
begin
  W := AImage.Width;
  H := AImage.Height;
  I := 0;
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      AImage.Colors[X, Y] := FastToFPColor(Pixels[I]);
      Inc(I);
    end;
end;

procedure LoadHaldToCube(AHaldClut: TFPCustomImage; Range: Integer; out Lut: TFastPixelArray);
var
  X, Y, Z, PX, PY, Idx: Integer;
begin
  SetLength(Lut, Range * Range * Range);
  for Z := 0 to Range - 1 do
    for Y := 0 to Range - 1 do
      for X := 0 to Range - 1 do
      begin
        Idx := X + Range * (Y + Range * Z);
        ClutPoint(X, Y, Z, Range, AHaldClut.Width, AHaldClut.Height, PX, PY);
        Lut[Idx] := FPColorToFast(AHaldClut.Colors[PX, PY]);
      end;
end;

procedure ApplyHaldClutToFastPixel(Work: PHaldWork; PixelIndex: PtrInt); inline;
var
  Src, Dst: TFastPixel;
  RV, GV, BV: Integer;
  X, Y, Z, XN, YN, ZN: Integer;
  FR, FG, FB: Integer;
  Rng, Rng2: Integer;
  Base000, Base001: Integer;
  Lut: ^TFastPixelArray;
begin
  Src := Work^.Pixels^[PixelIndex];
  Rng := Work^.Range;
  Rng2 := Rng * Rng;
  Lut := Work^.Lut;

  RV := Src.R * (Rng - 1);
  GV := Src.G * (Rng - 1);
  BV := Src.B * (Rng - 1);

  X := RV div 255; FR := RV mod 255;
  Y := GV div 255; FG := GV mod 255;
  Z := BV div 255; FB := BV mod 255;

  if X >= Rng - 1 then begin XN := X; FR := 0; end else XN := X + 1;
  if Y >= Rng - 1 then begin YN := Y; FG := 0; end else YN := Y + 1;
  if Z >= Rng - 1 then begin ZN := Z; FB := 0; end else ZN := Z + 1;

  Base000 := X + Rng * Y + Rng2 * Z;
  Base001 := X + Rng * Y + Rng2 * ZN;

  Dst := TrilinearInteger(
    Lut^[Base000],
    Lut^[XN + Rng * Y  + Rng2 * Z],
    Lut^[X  + Rng * YN + Rng2 * Z],
    Lut^[XN + Rng * YN + Rng2 * Z],
    Lut^[Base001],
    Lut^[XN + Rng * Y  + Rng2 * ZN],
    Lut^[X  + Rng * YN + Rng2 * ZN],
    Lut^[XN + Rng * YN + Rng2 * ZN],
    FR, FG, FB
  );

  Dst.A := Src.A;
  Work^.Pixels^[PixelIndex] := Dst;
end;

procedure ApplyHaldClutBlock(Index: PtrInt; Data: Pointer; Item: TMultiThreadProcItem);
var
  Work: PHaldWork;
  StartIndex, EndIndex, P: PtrInt;
begin
  Work := PHaldWork(Data);
  if Work = nil then Exit;

  if Item <> nil then
    Item.CalcBlock(Index, Work^.BlockSize, Work^.PixelCount, StartIndex, EndIndex)
  else
  begin
    StartIndex := 0;
    EndIndex := Work^.PixelCount - 1;
  end;

  for P := StartIndex to EndIndex do
    ApplyHaldClutToFastPixel(Work, P);
end;

procedure ApplyHaldClut(AImage, AHaldClut: TFPCustomImage);
var
  Work: THaldWork;
  Pixels: TFastPixelArray;
  Lut: TFastPixelArray;
  BlockCount, BlockSize: PtrInt;
begin
  if (AImage = nil) or (AHaldClut = nil) then Exit;
  if (AImage.Width <= 0) or (AImage.Height <= 0) then Exit;
  if (AHaldClut.Width <= 0) or (AHaldClut.Height <= 0) then Exit;

  if not IsProbablyHaldClut(AHaldClut, Work.Range) then
    raise Exception.CreateFmt('LUT dimensions do not look like a Hald CLUT: %dx%d',
      [AHaldClut.Width, AHaldClut.Height]);

  LoadImageToFast(AImage, Pixels);
  LoadHaldToCube(AHaldClut, Work.Range, Lut);

  Work.Pixels := @Pixels;
  Work.Lut := @Lut;
  Work.PixelCount := Length(Pixels);
  ProcThreadPool.CalcBlockSize(Work.PixelCount, BlockCount, BlockSize);
  Work.BlockSize := BlockSize;

  if BlockCount <= 1 then
    ApplyHaldClutBlock(0, @Work, nil)
  else
    ProcThreadPool.DoParallel(@ApplyHaldClutBlock, 0, BlockCount - 1, @Work);

  StoreFastToImage(Pixels, AImage);
end;

end.
