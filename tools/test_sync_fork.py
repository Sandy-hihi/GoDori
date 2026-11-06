"""실제 로컬 Git 저장소로 포크 동기화 스크립트를 검증합니다. 네트워크는 쓰지 않습니다."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / '.github' / 'scripts' / 'sync-fork.sh'
BASH = (r'C:\Program Files\Git\bin\bash.exe'
        if os.name == 'nt' else shutil.which('bash'))


class SyncForkTest(unittest.TestCase):
    def setUp(self):
        cache = ROOT / '.dart_tool' / 'fork_sync_tests'
        cache.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=cache)
        # 정리할 임시 경로가 이 테스트 전용 작업 폴더 안인지 확인합니다.
        self.assertTrue(Path(self.temp.name).resolve().is_relative_to(cache.resolve()))
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / 'source'
        self.remote = Path(self.temp.name) / 'fork.git'
        self.source.mkdir()
        self.git('init', '--quiet', cwd=self.source)
        self.git('init', '--quiet', '--bare', str(self.remote), cwd=self.source)
        self.git('-c', 'user.name=Sync Test', '-c', 'user.email=sync@example.invalid',
                 'commit', '--quiet', '--allow-empty', '-m', 'initial', cwd=self.source)

    def git(self, *args, cwd, check=True):
        return subprocess.run(['git', *args], cwd=cwd, check=check,
                              capture_output=True, text=True)

    def sync(self, ref, check=True):
        env = dict(os.environ, SYNC_REF=ref, FORK_REMOTE=self.remote.as_uri())
        # Git Bash와 같은 배포 환경에서 실행합니다.
        return subprocess.run([BASH, str(SCRIPT)], cwd=self.source, env=env,
                              check=check, capture_output=True, text=True)

    def test_branch_with_slash(self):
        self.sync('refs/heads/feature/pad-login')
        expected = self.git('rev-parse', 'HEAD', cwd=self.source).stdout
        actual = self.git('rev-parse', 'refs/heads/feature/pad-login', cwd=self.remote).stdout
        self.assertEqual(expected, actual)

    def test_annotated_tag_preserves_tag_object_without_extra_branch_or_tags(self):
        self.git('-c', 'user.name=Sync Test', '-c', 'user.email=sync@example.invalid',
                 'tag', '-a', 'release/v1', '-m', 'release', cwd=self.source)
        self.git('tag', 'unrelated', cwd=self.source)
        self.sync('refs/tags/release/v1')
        expected = self.git('rev-parse', 'refs/tags/release/v1', cwd=self.source).stdout
        actual = self.git('rev-parse', 'refs/tags/release/v1', cwd=self.remote).stdout
        self.assertEqual(expected, actual)
        for ref in ['refs/heads/release/v1', 'refs/tags/unrelated']:
            self.assertNotEqual(self.git('show-ref', '--verify', ref,
                                        cwd=self.remote, check=False).returncode, 0)

    def test_other_ref_namespaces_are_rejected(self):
        self.assertNotEqual(self.sync('refs/pull/1/head', check=False).returncode, 0)
        self.assertEqual(self.git('for-each-ref', cwd=self.remote).stdout, '')


if __name__ == '__main__':
    unittest.main()
