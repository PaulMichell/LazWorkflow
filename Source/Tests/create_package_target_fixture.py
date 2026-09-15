#!/usr/bin/python3
"""Create a NEW disposable workspace for codex_package_fixture.py.

Usage: create_package_target_fixture.py /tmp/package-target-check
Refuses to overwrite an existing directory. Does not configure accounts or IDEs.
"""
import sys
from pathlib import Path


def create(root):
    root.mkdir(parents=True, exist_ok=False)
    for name in ('Packages', 'Source', 'App', 'Documents'):
        (root / name).mkdir()
    (root / 'Packages/PackageTargetCheck.lpk').write_text('''<?xml version="1.0"?>
<CONFIG><Package Version="5">
<Name Value="PackageTargetCheck"/><Type Value="RunTimeOnly"/>
<CompilerOptions><Version Value="11"/><SearchPaths>
<OtherUnitFiles Value="../Source"/>
<UnitOutputDirectory Value="../lib/$(TargetCPU)-$(TargetOS)"/>
</SearchPaths></CompilerOptions>
<Files Count="1"><Item1><Filename Value="../Source/PackageUnit.pas"/>
<UnitName Value="PackageUnit"/></Item1></Files>
<UsageOptions><UnitPath Value="$(PkgOutDir)"/></UsageOptions>
</Package></CONFIG>
''')
    (root / 'Source/PackageUnit.pas').write_text('''unit PackageUnit;
{$mode objfpc}
interface
function Answer: Integer;
implementation
function Answer: Integer;
begin
  Result := 42;
end;
end.
''')
    (root / 'App/Unrelated.lpr').write_text("program Unrelated;\nbegin\n  WriteLn('unrelated');\nend.\n")
    (root / 'App/Unrelated.lpi').write_text('''<?xml version="1.0"?>
<CONFIG><ProjectOptions><Version Value="12"/><General>
<MainUnit Value="0"/><Title Value="Unrelated"/><UseAppBundle Value="False"/>
</General><Units Count="1"><Unit0><Filename Value="Unrelated.lpr"/>
<IsPartOfProject Value="True"/></Unit0></Units></ProjectOptions>
<CompilerOptions><Version Value="11"/><Target><Filename Value="Unrelated"/>
</Target></CompilerOptions></CONFIG>
''')
    (root / 'TestAnswer.pas').write_text("program TestAnswer;\nuses PackageUnit;\nbegin if Answer <> 43 then Halt(1); WriteLn('Answer behaviour passed'); end.\n")
    (root / 'run_tests.py').write_text('''import subprocess
from pathlib import Path
root = Path(__file__).resolve().parent
# Match the Lazarus package output directory on the test machine.
cpu = subprocess.check_output(['fpc', '-iTP'], text=True).strip()
os_name = subprocess.check_output(['fpc', '-iTO'], text=True).strip()
subprocess.run(['fpc', '-Fu' + str(root / 'lib' / (cpu + '-' + os_name)),
                '-FE' + str(root / 'lib'), '-FU' + str(root / 'lib'),
                str(root / 'TestAnswer.pas')], check=True)
subprocess.run([str(root / 'lib' / ('TestAnswer.exe' if os_name.startswith('win') else 'TestAnswer'))], check=True)
''')
    print(root.resolve())


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    create(Path(sys.argv[1]).resolve())
