@echo off
setlocal enabledelayedexpansion

rem
rem build architecture
rem

if "%1" equ "x64" (
  set ARCH=x64
) else if "%1" equ "arm64" (
  set ARCH=arm64
) else if "%1" neq "" (
  echo Unknown target "%1" architecture!
  exit /b 1
) else if "%PROCESSOR_ARCHITECTURE%" equ "AMD64" (
  set ARCH=x64
) else if "%PROCESSOR_ARCHITECTURE%" equ "ARM64" (
  set ARCH=arm64
)

rem
rem dependencies
rem

where /q git.exe || (
  echo ERROR: "git.exe" not found
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

for /f "tokens=*" %%i in ('"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath') do set VS=%%i
if "%VS%" equ "" (
  echo ERROR: Visual Studio installation not found
  exit /b 1
)

rem
rem get depot tools
rem

set PATH=%CD%\depot_tools;%PATH%
set DEPOT_TOOLS_WIN_TOOLCHAIN=0

if not exist depot_tools (
  call git clone --depth=1 --no-tags --single-branch https://chromium.googlesource.com/chromium/tools/depot_tools.git || exit /b 1
)

rem
rem clone angle source
rem

if "%ANGLE_COMMIT%" equ "" (
  for /f "tokens=1 usebackq" %%F IN (`git ls-remote https://chromium.googlesource.com/angle/angle HEAD`) do set ANGLE_COMMIT=%%F
)

if not exist angle (
  call git init angle                                                               || exit /b 1
  call git -C angle remote add origin https://chromium.googlesource.com/angle/angle || exit /b 1
)

call git -C angle fetch --no-recurse-submodules origin %ANGLE_COMMIT% || exit /b 1
call git -C angle reset --hard FETCH_HEAD                             || exit /b 1

pushd angle

python.exe scripts\bootstrap.py || exit /b 1

"C:\Program Files\Git\usr\bin\sed.exe" -i.bak -e "/'third_party\/catapult'\: /,+3d" -e "/'third_party\/dawn'\: /,+3d" -e "/'third_party\/llvm\/src'\: /,+3d" -e "/'third_party\/VK-GL-CTS\/src'\: /,+3d" DEPS || exit /b 1
call gclient sync -f -D -R || exit /b 1

popd

rem
rem build angle
rem

pushd angle

call gn gen out/%ARCH% --args="target_cpu=""%ARCH%"" angle_build_all=false is_debug=false angle_has_frame_capture=false angle_enable_gl=true angle_enable_vulkan=true angle_enable_wgpu=false angle_enable_d3d11=true angle_enable_null=false use_siso=false" || exit /b 1
"C:\Program Files\Git\usr\bin\sed.exe" -i.bak -e "s/\/MD/\/MT/" build\config\win\BUILD.gn || exit /b 1

set CL=/Z7
set LINK=/OPT:REF /OPT:ICF /DEBUG /PDBALTPATH:%%_PDB%%
call autoninja --offline -C out/%ARCH% libEGL libGLESv2 libGLESv1_CM || exit /b 1

popd

rem *** prepare output folder ***

call "%VS%\Common7\Tools\VsDevCmd.bat" -arch=%ARCH% -startdir=none -no_logo || exit /b 1
set PATH="%WindowsSdkDir%\Debuggers\x64";%PATH%

mkdir angle-%ARCH%         1>nul
mkdir angle-%ARCH%\bin     1>nul
mkdir angle-%ARCH%\lib     1>nul
mkdir angle-%ARCH%\include 1>nul

echo %ANGLE_COMMIT% > angle-%ARCH%\commit.txt

copy /y angle\out\%ARCH%\d3dcompiler_47.dll          angle-%ARCH%\bin                         1>nul 2>nul
copy /y angle\out\%ARCH%\libEGL.dll                  angle-%ARCH%\bin                         1>nul 2>nul
copy /y angle\out\%ARCH%\libGLESv1_CM.dll            angle-%ARCH%\bin                         1>nul 2>nul
copy /y angle\out\%ARCH%\libGLESv2.dll               angle-%ARCH%\bin                         1>nul 2>nul

pdbcopy.exe angle\out\%ARCH%\libEGL.dll.pdb          angle-%ARCH%\bin\libEGL.dll.pdb       -p 1>nul 2>nul
pdbcopy.exe angle\out\%ARCH%\libGLESv1_CM.dll.pdb    angle-%ARCH%\bin\libGLESv1_CM.dll.pdb -p 1>nul 2>nul
pdbcopy.exe angle\out\%ARCH%\libGLESv2.dll.pdb       angle-%ARCH%\bin\libGLESv2.dll.pdb    -p 1>nul 2>nul

copy /y angle\out\%ARCH%\libEGL.dll.lib              angle-%ARCH%\lib                         1>nul 2>nul
copy /y angle\out\%ARCH%\libGLESv1_CM.dll.lib        angle-%ARCH%\lib                         1>nul 2>nul
copy /y angle\out\%ARCH%\libGLESv2.dll.lib           angle-%ARCH%\lib                         1>nul 2>nul

xcopy /D /S /I /Q /Y angle\include\KHR               angle-%ARCH%\include\KHR                 1>nul 2>nul
xcopy /D /S /I /Q /Y angle\include\EGL               angle-%ARCH%\include\EGL                 1>nul 2>nul
xcopy /D /S /I /Q /Y angle\include\GLES              angle-%ARCH%\include\GLES                1>nul 2>nul
xcopy /D /S /I /Q /Y angle\include\GLES2             angle-%ARCH%\include\GLES2               1>nul 2>nul
xcopy /D /S /I /Q /Y angle\include\GLES3             angle-%ARCH%\include\GLES3               1>nul 2>nul

del /Q /S angle-%ARCH%\include\*.clang-format angle-%ARCH%\include\*.md 1>nul 2>nul

rem
rem Done!
rem

if "%GITHUB_WORKFLOW%" neq "" (

  rem
  rem GitHub actions stuff
  rem

  %SZIP% a -mx=9 angle-%ARCH%-%BUILD_DATE%.zip angle-%ARCH% || exit /b 1
)
