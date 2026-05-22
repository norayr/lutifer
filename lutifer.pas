program lutifer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, Math,
  FPImage,
  FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGIF, FPReadTIFF,
  FPWritePNG, FPWriteJPEG, FPWriteBMP,
  haldclut;

const
  ExitOK = 0;
  ExitUsage = 1;
  ExitFailure = 2;
  DefaultJPEGQuality = 92;

type
  TOptions = record
    InputFile: String;
    LutFile: String;
    OutputFile: String;
    Verbose: Boolean;
    JPEGQuality: Integer;
  end;

procedure PrintUsage;
begin
  WriteLn('lutifer - apply a Hald CLUT PNG to an image');
  WriteLn;
  WriteLn('Usage:');
  WriteLn('  lutifer -i input.jpg -l lut.png -o out.jpg');
  WriteLn('  lutifer input.jpg lut.png out.jpg');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -i, --input FILE       input image');
  WriteLn('  -l, --lut FILE         Hald CLUT image, usually PNG');
  WriteLn('  -o, --output FILE      output image');
  WriteLn('  -q, --quality N        JPEG quality, 1..100; default ', DefaultJPEGQuality);
  WriteLn('  -v, --verbose          print progress messages');
  WriteLn('  -h, --help             show this help');
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

function ParseQuality(const S: String): Integer;
begin
  if not TryStrToInt(S, Result) then
    FailUsage('JPEG quality must be a number from 1 to 100');
  if (Result < 1) or (Result > 100) then
    FailUsage('JPEG quality must be from 1 to 100');
end;

procedure ParseOptions(out Opt: TOptions);
var
  I: Integer;
  A: String;
begin
  FillChar(Opt, SizeOf(Opt), 0);
  Opt.JPEGQuality := DefaultJPEGQuality;

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

      '-q', '--quality', '--jpeg-quality':
        Opt.JPEGQuality := ParseQuality(NeedValue(A, I));

    else
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

function NewImage: TFPMemoryImage;
begin
  Result := TFPMemoryImage.Create(0, 0);
end;

procedure LoadImage(AImage: TFPMemoryImage; const AFileName: String);
begin
  AImage.LoadFromFile(AFileName);
  if (AImage.Width <= 0) or (AImage.Height <= 0) then
    raise Exception.Create('unsupported or empty image: ' + AFileName);
end;

procedure SaveImage(AImage: TFPMemoryImage; const AFileName: String; JPEGQuality: Integer);
var
  Ext: String;
  Png: TFPWriterPNG;
  Jpg: TFPWriterJPEG;
  Bmp: TFPWriterBMP;
begin
  if (AImage = nil) or (AImage.Width <= 0) or (AImage.Height <= 0) then
    raise Exception.Create('refusing to save an empty image');

  Ext := LowerCase(ExtractFileExt(AFileName));

  if (Ext = '.jpg') or (Ext = '.jpeg') then
  begin
    Jpg := TFPWriterJPEG.Create;
    try
      Jpg.CompressionQuality := JPEGQuality;
      AImage.SaveToFile(AFileName, Jpg);
    finally
      Jpg.Free;
    end;
  end
  else if Ext = '.bmp' then
  begin
    Bmp := TFPWriterBMP.Create;
    try
      AImage.SaveToFile(AFileName, Bmp);
    finally
      Bmp.Free;
    end;
  end
  else
  begin
    Png := TFPWriterPNG.Create;
    try
      AImage.SaveToFile(AFileName, Png);
    finally
      Png.Free;
    end;
  end;
end;

procedure Run;
var
  Opt: TOptions;
  InputImg: TFPMemoryImage;
  LutImg: TFPMemoryImage;
  Range: Integer;
begin
  ParseOptions(Opt);

  CheckReadableFile(Opt.InputFile, 'input');
  CheckReadableFile(Opt.LutFile, 'LUT');

  InputImg := NewImage;
  LutImg := NewImage;
  try
    if Opt.Verbose then
      WriteLn('loading input: ', Opt.InputFile);
    LoadImage(InputImg, Opt.InputFile);

    if Opt.Verbose then
      WriteLn('loading LUT: ', Opt.LutFile);
    LoadImage(LutImg, Opt.LutFile);

    if not IsProbablyHaldClut(LutImg, Range) then
      raise Exception.CreateFmt(
        'LUT dimensions do not look like a Hald CLUT: %dx%d',
        [LutImg.Width, LutImg.Height]
      );

    if Opt.Verbose then
    begin
      WriteLn('input size: ', InputImg.Width, 'x', InputImg.Height);
      WriteLn('Hald CLUT range: ', Range, ' (', LutImg.Width, 'x', LutImg.Height, ')');
      WriteLn('applying LUT using headless fcl-image / MTProcs...');
    end;

    ApplyHaldClut(InputImg, LutImg);

    if Opt.Verbose then
      WriteLn('saving output: ', Opt.OutputFile);
    SaveImage(InputImg, Opt.OutputFile, Opt.JPEGQuality);

    if Opt.Verbose then
      WriteLn('done');
  finally
    LutImg.Free;
    InputImg.Free;
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
