@echo off
setlocal enabledelayedexpansion

if "%1" equ "GL" (
  set BACK=GL
) else if "%1" equ "DX" (
  set BACK=DX
) else if "%1" equ "Vulkan" (
  set BACK=Vulkan
) else if "%1" neq "" (
  echo Unknown backend^^!
  exit /b 1
) else (
  set BACK=GL
)

set CONFIG=Release

set PATH=%CD%\depot_tools;%PATH%

rem *** check dependencies ***

where /q python.exe || (
  echo ERROR: "python.exe" not found
  exit /b 1
)

where /q git.exe || (
  echo ERROR: "git.exe" not found
  exit /b 1
)

where /q curl.exe || (
  echo ERROR: "curl.exe" not found
  exit /b 1
)

if exist "%ProgramFiles%\7-Zip\7z.exe" (
  set SZIP="%ProgramFiles%\7-Zip\7z.exe"
) else (
  where /q 7za.exe || (
    echo ERROR: 7-Zip installation or "7za.exe" not found
    exit /b 1
  )
  set SZIP=7za.exe
)

for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -version [17.0^,18.0^) -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath`) do set VS=%%i
if "!VS!" equ "" (
  echo ERROR: Visual Studio 2022 installation not found
  exit /b 1
)  

rem *** download depot_tools ***

if not exist depot_tools (
  mkdir depot_tools
  pushd depot_tools
  curl -LOsf https://storage.googleapis.com/chrome-infra/depot_tools.zip || exit /b 1
  %SZIP% x -bb0 -y depot_tools.zip 1>nul 2>nul || exit /b 1
  del depot_tools.zip 1>nul 2>nul
  popd
)

rem *** downlaod angle source ***

if exist angle.src (
  pushd angle.src
  pushd build
  call git reset --hard HEAD
  popd
  call git pull --force --no-tags --depth 1
  popd
) else (
  call git clone --single-branch --no-tags --depth 1 https://chromium.googlesource.com/angle/angle angle.src || exit /b 1
  pushd angle.src
  python scripts\bootstrap.py || exit /b 1
  popd
)

rem *** build angle ***

pushd angle.src

set DEPOT_TOOLS_WIN_TOOLCHAIN=0
call gclient sync || exit /b 1

if "%BACK%" equ "GL" (
  call gn gen out/%CONFIG%%BACK% --args="angle_build_all=false is_debug=false angle_has_frame_capture=false angle_enable_gl=true angle_enable_vulkan=false angle_enable_d3d9=false angle_enable_d3d11=false angle_enable_null=false" || exit /b 1
) else if "%BACK%" equ "DX" (
  call gn gen out/%CONFIG%%BACK% --args="angle_build_all=false is_debug=false angle_has_frame_capture=false angle_enable_gl=false angle_enable_vulkan=false angle_enable_d3d9=false angle_enable_null=false" || exit /b 1
) else if "%BACK%" equ "Vulkan" (
  call gn gen out/%CONFIG%%BACK% --args="angle_build_all=false is_debug=false angle_has_frame_capture=false angle_enable_gl=false angle_enable_vulkan=true angle_enable_d3d9=false angle_enable_d3d11=false angle_enable_null=false" || exit /b 1
)
call git apply -p0 ..\angle.patch || exit /b 1
call autoninja -C out/%CONFIG%%BACK% libEGL libGLESv2 libGLESv1_CM || exit /b 1

popd

rem *** prepare output folder ***

rmdir /q /s bin\%BACK% 1>nul 2>nul

mkdir bin\%BACK%\bin
mkdir bin\%BACK%\lib
mkdir bin\%BACK%\include

copy /y angle.src\.git\refs\heads\main bin\%BACK%\commit.txt 1>nul 2>nul

copy /y "%ProgramFiles(x86)%\Windows Kits\10\Redist\D3D\x64\d3dcompiler_47.dll" bin\%BACK%\bin 1>nul 2>nul

copy /y angle.src\out\%CONFIG%%BACK%\libEGL.dll       bin\%BACK%\bin        1>nul 2>nul
copy /y angle.src\out\%CONFIG%%BACK%\libGLESv1_CM.dll bin\%BACK%\bin        1>nul 2>nul
copy /y angle.src\out\%CONFIG%%BACK%\libGLESv2.dll    bin\%BACK%\bin        1>nul 2>nul
copy /y angle.src\out\%CONFIG%%BACK%\vulkan-1.dll     bin\%BACK%\bin        1>nul 2>nul

copy /y angle.src\out\%CONFIG%%BACK%\libEGL.dll.lib       bin\%BACK%\lib    1>nul 2>nul
copy /y angle.src\out\%CONFIG%%BACK%\libGLESv1_CM.dll.lib bin\%BACK%\lib    1>nul 2>nul
copy /y angle.src\out\%CONFIG%%BACK%\libGLESv2.dll.lib    bin\%BACK%\lib    1>nul 2>nul

xcopy /D /S /I /Q /Y angle.src\include\KHR   bin\%BACK%\include\KHR   1>nul 2>nul
xcopy /D /S /I /Q /Y angle.src\include\EGL   bin\%BACK%\include\EGL   1>nul 2>nul
xcopy /D /S /I /Q /Y angle.src\include\GLES  bin\%BACK%\include\GLES  1>nul 2>nul
xcopy /D /S /I /Q /Y angle.src\include\GLES2 bin\%BACK%\include\GLES2 1>nul 2>nul
xcopy /D /S /I /Q /Y angle.src\include\GLES3 bin\%BACK%\include\GLES3 1>nul 2>nul

del /Q /S bin\%BACK%\include\*.clang-format 1>nul 2>nul

rem *** done ***
rem output is in angle folder

if "%GITHUB_WORKFLOW%" neq "" (
  set /p ANGLE_COMMIT=<bin\%BACK%\commit.txt

  for /F "skip=1" %%D in ('WMIC OS GET LocalDateTime') do (set LDATE=%%D & goto :dateok)
  :dateok
  set BUILD_DATE=%LDATE:~0,4%-%LDATE:~4,2%-%LDATE:~6,2%

  %SZIP% a -mx=9 angle-%BUILD_DATE%.zip angle || exit /b 1

  echo ::set-output name=ANGLE_COMMIT::%ANGLE_COMMIT%
  echo ::set-output name=BUILD_DATE::%BUILD_DATE%
)
