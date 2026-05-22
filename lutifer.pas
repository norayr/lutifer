program lutifer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Classes, SysUtils, Math,
  Graphics,
  FPImage,
  FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGIF, FPReadTIFF,
  FPWritePNG, FPWriteJPEG, FPWriteBMP,
  haldclut;

const
  ExitOK = 0;
  ExitUsage = 1;
  ExitFailure = 2;

type
  TOptions = record
    InputFile: String;
    LutFile: String;
    OutputFile: String;
    Verbose: Boolean;
  end;

procedure PrintUsage;
begin
  WriteLn('lutifer - apply a Hald CLUT PNG to an image');
  WriteLn;
  WriteLn('Usage:');
  WriteLn('  lutifer -i input.jpg -l lut.png -o out.png');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -i, --input FILE     input image');
  WriteLn('  -l, --lut FILE       Hald CLUT image, usually PNG');
  WriteLn('  -o, --output FILE    output image');
  WriteLn('  -v, --verbose        print progress messages');
  WriteLn('  -h, --help           show this help');
  WriteLn;
  WriteLn('Output format is inferred from the output extension: .png, .jpg/.jpeg, .bmp.');
end;

procedure FailUsage(const Msg: String);
begin
  if Msg <> '' then
    WriteLn(StdErr, 'lutifer: ', Msg);
  WriteLn(StdErr, 'Try: lutifer --help');
  Halt(ExitUsage);
end;

function NeedValue(const Opt: String; var I: Integer): String;
begin
  if I >= ParamCount then
    FailUsage('missing value after ' + Opt);
  Inc(I);
  Result := ParamStr(I);
  if Result = '' then
    FailUsage('empty value after ' + Opt);
end;

procedure ParseOptions(out Opt: TOptions);
var
  I: Integer;
  A: String;
begin
  FillChar(Opt, SizeOf(Opt), 0);

  I := 1;
  while I <= ParamCount do
  begin
    A := ParamStr(I);

    case A of
      '-h', '--help':
        begin
          PrintUsage;
          Halt(ExitOK);
        end;

      '-v', '--verbose':
        Opt.Verbose := True;

      '-i', '--input':
        Opt.InputFile := NeedValue(A, I);

      '-l', '--lut':
        Opt.LutFile := NeedValue(A, I);

      '-o', '--output':
        Opt.OutputFile := NeedValue(A, I);

    else
      { Convenience form:
          lutifer input.jpg lut.png out.png
        This keeps the short form useful without making the documented
        -i/-l/-o interface ambiguous.
      }
      if (A <> '') and (A[1] <> '-') then
      begin
        if Opt.InputFile = '' then
          Opt.InputFile := A
        else if Opt.LutFile = '' then
          Opt.LutFile := A
        else if Opt.OutputFile = '' then
          Opt.OutputFile := A
        else
          FailUsage('unexpected extra argument: ' + A);
      end
      else
        FailUsage('unknown option: ' + A);
    end;

    Inc(I);
  end;

  if Opt.InputFile = '' then
    FailUsage('input file is required');
  if Opt.LutFile = '' then
    FailUsage('LUT file is required');
  if Opt.OutputFile = '' then
    FailUsage('output file is required');
end;

procedure CheckReadableFile(const FileName, What: String);
begin
  if not FileExists(FileName) then
    raise Exception.CreateFmt('%s file not found: %s', [What, FileName]);
end;

function IsProbablyHaldClut(ABitmap: TBitmap; out Range: Integer): Boolean;
var
  Pixels, Cube: Double;
begin
  Result := False;
  Range := 0;

  if (ABitmap = nil) or (ABitmap.Width <= 0) or (ABitmap.Height <= 0) then
    Exit;

  Pixels := Double(ABitmap.Width) * Double(ABitmap.Height);
  Cube := Power(Pixels, 1.0 / 3.0);
  Range := Round(Cube);

  Result :=
    (Range >= 2) and
    (Int64(Range) * Int64(Range) * Int64(Range) =
      Int64(ABitmap.Width) * Int64(ABitmap.Height));
end;

procedure LoadBitmapFromAnyFile(ABitmap: TBitmap; const AFileName: String);
var
  Pic: TPicture;
begin
  Pic := TPicture.Create;
  try
    Pic.LoadFromFile(AFileName);

    if (Pic.Width <= 0) or (Pic.Height <= 0) or (Pic.Graphic = nil) then
      raise Exception.Create('unsupported or empty image: ' + AFileName);

    ABitmap.SetSize(Pic.Width, Pic.Height);
    ABitmap.Canvas.Brush.Color := clBlack;
    ABitmap.Canvas.FillRect(0, 0, ABitmap.Width, ABitmap.Height);
    ABitmap.Canvas.Draw(0, 0, Pic.Graphic);
  finally
    Pic.Free;
  end;
end;

procedure SaveBitmapToFile(ABitmap: TBitmap; const AFileName: String);
var
  Ext: String;
  Png: TPortableNetworkGraphic;
  Jpg: TJPEGImage;
begin
  if (ABitmap = nil) or (ABitmap.Width <= 0) or (ABitmap.Height <= 0) then
    raise Exception.Create('refusing to save an empty bitmap');

  Ext := LowerCase(ExtractFileExt(AFileName));

  if Ext = '.bmp' then
    ABitmap.SaveToFile(AFileName)
  else if (Ext = '.jpg') or (Ext = '.jpeg') then
  begin
    Jpg := TJPEGImage.Create;
    try
      Jpg.Assign(ABitmap);
      Jpg.SaveToFile(AFileName);
    finally
      Jpg.Free;
    end;
  end
  else
  begin
    Png := TPortableNetworkGraphic.Create;
    try
      Png.Assign(ABitmap);
      Png.SaveToFile(AFileName);
    finally
      Png.Free;
    end;
  end;
end;

procedure Run;
var
  Opt: TOptions;
  InputBmp: TBitmap;
  LutBmp: TBitmap;
  Range: Integer;
begin
  ParseOptions(Opt);

  CheckReadableFile(Opt.InputFile, 'input');
  CheckReadableFile(Opt.LutFile, 'LUT');

  InputBmp := TBitmap.Create;
  LutBmp := TBitmap.Create;
  try
    if Opt.Verbose then
      WriteLn('loading input: ', Opt.InputFile);
    LoadBitmapFromAnyFile(InputBmp, Opt.InputFile);

    if Opt.Verbose then
      WriteLn('loading LUT: ', Opt.LutFile);
    LoadBitmapFromAnyFile(LutBmp, Opt.LutFile);

    if not IsProbablyHaldClut(LutBmp, Range) then
      raise Exception.CreateFmt(
        'LUT dimensions do not look like a Hald CLUT: %dx%d',
        [LutBmp.Width, LutBmp.Height]
      );

    if Opt.Verbose then
    begin
      WriteLn('input size: ', InputBmp.Width, 'x', InputBmp.Height);
      WriteLn('Hald CLUT range: ', Range, ' (', LutBmp.Width, 'x', LutBmp.Height, ')');
      WriteLn('applying LUT using haldclut_laz / MTProcs...');
    end;

    ApplyHaldClut(InputBmp, LutBmp);

    if Opt.Verbose then
      WriteLn('saving output: ', Opt.OutputFile);
    SaveBitmapToFile(InputBmp, Opt.OutputFile);

    if Opt.Verbose then
      WriteLn('done');
  finally
    LutBmp.Free;
    InputBmp.Free;
  end;
end;

begin
  try
    Run;
    Halt(ExitOK);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, 'lutifer: ', E.Message);
      Halt(ExitFailure);
    end;
  end;
end.
