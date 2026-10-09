#!/bin/bash
# Builds bin/BrickGen.Core.dll from csharp/BrickGen.Core/*.cs (netstandard2.0,
# loads in 3ds Max with .NET Framework and with .NET 8).
#
# Needs a C# compiler. Without a .NET SDK, the NuGet packages are enough:
#   runtime.linux-x64.microsoft.netcore.dotnethost 8.0.0   (dotnet host)
#   microsoft.netcore.app.runtime.linux-x64 8.0.0          (runtime)
#   microsoft.net.compilers.toolset 4.8.0                  (csc.dll)
#   netstandard.library 2.0.3                              (reference assemblies)
# With a .NET SDK installed: set DOTNET=dotnet and CSC to the SDK's csc.dll.
#
# usage: DOTNET=/path/dotnet CSC=/path/csc.dll NSREF=/path/netstandard2.0/ref tools/build_native.sh
set -e
cd "$(dirname "$0")/.."
: "${DOTNET:?set DOTNET}" "${CSC:?set CSC}" "${NSREF:?set NSREF (netstandard.library/build/netstandard2.0/ref)}"
REFS=""
for r in "$NSREF"/*.dll; do REFS="$REFS -r:$r"; done
mkdir -p bin
"$DOTNET" "$CSC" -nologo -target:library -optimize+ -deterministic -nostdlib+ -noconfig $REFS \
  -out:bin/BrickGen.Core.dll csharp/BrickGen.Core/*.cs
echo "bin/BrickGen.Core.dll built"
