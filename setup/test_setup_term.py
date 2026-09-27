import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("setup_term.sh")
PLUGINS = {
    "zsh-autocomplete": "zsh-autocomplete.plugin.zsh",
    "zsh-autosuggestions": "zsh-autosuggestions.zsh",
    "zsh-syntax-highlighting": "zsh-syntax-highlighting.zsh",
}
LEGACY_BLOCKS = """
# Ensure autosuggestions loads
if [ -f "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Ensure autocomplete loads
if [ -f "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh" ]; then
  source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh"
fi

# Ensure syntax highlighting loads (keep this near the end of ~/.zshrc)
if [ -f "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
"""
MANUAL_FIX = """
# Load autocomplete before Oh My Zsh initializes completion.
source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh"
source $ZSH/oh-my-zsh.sh
# Preserve autocomplete's bindings after Oh My Zsh's defaults.
bindkey '^[[A' up-line-or-search '^[OA' up-line-or-search
bindkey '^[[B' down-line-or-select '^[OB' down-line-or-select
if [[ -n "${terminfo[kcbt]}" ]]; then
  bindkey "${terminfo[kcbt]}" expand-word
fi
"""


@unittest.skipUnless(shutil.which("zsh") and shutil.which("perl"), "requires zsh and perl")
class TerminalSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="setup-term-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home
        self.custom = self.home / ".oh-my-zsh/custom"
        self.env = os.environ.copy()
        for key in ("ZDOTDIR", "ZSH", "ZSH_CUSTOM", "ZSH_COMPDUMP", "STARSHIP_CONFIG"):
            self.env.pop(key, None)
        self.env.update(
            HOME=str(self.home),
            XDG_CACHE_HOME=str(self.home / ".cache"),
            XDG_CONFIG_HOME=str(self.home / ".config"),
            LOAD_LOG=str(self.home / "loads"),
            TERM="xterm-256color",
        )
        for plugin, filename in PLUGINS.items():
            directory = self.custom / "plugins" / plugin
            directory.mkdir(parents=True)
            (directory / filename).write_text(
                f'print -r -- "{plugin}" >> "$LOAD_LOG"\n'
            )
            entry = directory / f"{plugin}.plugin.zsh"
            if not entry.exists():
                entry.write_text(f'source "{directory / filename}"\n')
        (self.home / ".oh-my-zsh/oh-my-zsh.sh").write_text(
            '[[ "$skip_global_compinit" == 1 ]] || return 1\n'
            'print -r -- oh-my-zsh >> "$LOAD_LOG"\n'
            'for plugin in $plugins; do\n'
            '  file="${ZSH_CUSTOM:-$ZSH/custom}/plugins/$plugin/$plugin.plugin.zsh"\n'
            '  [[ ! -f "$file" ]] || source "$file"\n'
            'done\n'
            "bindkey '^[[A' up-line-or-history\n"
        )

    def write_rc(self, text):
        self.config.mkdir(parents=True, exist_ok=True)
        (self.config / ".zshrc").write_text(text)

    def run_setup(self, full=False, success=True):
        if full:
            command = [
                "bash", "-c",
                'source "$1" --help >/dev/null; '
                'install_packages() { :; }; install_oh_my_zsh() { :; }; '
                'git_clone_or_update() { :; }; ensure_starship_config() { :; }; '
                'offer_set_default_shell() { :; }; main',
                "test-setup", str(SCRIPT),
            ]
        else:
            command = ["bash", str(SCRIPT), "--repair-zsh"]
        result = subprocess.run(command, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def assert_startup(self):
        log = Path(self.env["LOAD_LOG"])
        if log.exists():
            log.unlink()
        result = subprocess.run(
            ["zsh", "-i", "-c", "bindkey '^[[A'; bindkey '^[OA'; print -r -- $plugins"],
            env=self.env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("command not found", result.stderr)
        self.assertEqual(
            log.read_text().splitlines(),
            ["zsh-autocomplete", "oh-my-zsh", "zsh-autosuggestions",
             "zsh-syntax-highlighting"],
        )
        self.assertEqual(result.stdout.count("up-line-or-search"), 2)
        return result.stdout

    def assert_idempotent(self, full=False):
        before = [(self.config / name).read_bytes() for name in (".zshrc", ".zshenv")]
        self.run_setup(full=full)
        after = [(self.config / name).read_bytes() for name in (".zshrc", ".zshenv")]
        self.assertEqual(before, after)

    def test_fresh_setup_and_full_rerun(self):
        self.run_setup(full=True)
        rc = (self.config / ".zshrc").read_text()
        self.assertLess(rc.index("# >>> setup_term.sh: completion"), rc.index("# Starship prompt"))
        self.assertIn("git", self.assert_startup())
        self.assert_idempotent(full=True)
        self.assert_startup()

    def test_legacy_multiline_plugins_and_sources(self):
        original = (
            'export ZSH="$HOME/.oh-my-zsh"\n'
            'plugins=(\n git\n "zsh-autocomplete"\n zsh-autosuggestions\n'
            " 'zsh-syntax-highlighting'\n python # keep this comment\n)\n"
            "source $ZSH/oh-my-zsh.sh\n" + LEGACY_BLOCKS
            + "\nalias mycommand='echo preserved'\n"
        )
        self.write_rc(original)
        self.run_setup()
        self.assertIn("python", self.assert_startup())
        repaired = (self.config / ".zshrc").read_text()
        self.assertIn("alias mycommand='echo preserved'", repaired)
        self.assertIn("# keep this comment", repaired)
        self.assertEqual(
            next(self.config.glob(".zshrc.setup-term-backup.*")).read_text(), original
        )
        self.assert_idempotent()
        self.assert_startup()

    def test_existing_manual_fix(self):
        self.write_rc(
            'export ZSH="$HOME/.oh-my-zsh"\n'
            "plugins=(git zsh-autosuggestions zsh-syntax-highlighting)\n"
            + MANUAL_FIX + LEGACY_BLOCKS
        )
        (self.config / ".zshenv").write_text("skip_global_compinit=1\n")
        self.run_setup()
        self.assert_startup()
        self.assert_idempotent()

    def test_late_plugin_list_and_direct_compinit(self):
        self.write_rc(
            'export ZSH="$HOME/.oh-my-zsh"\n'
            "autoload -Uz compinit\n"
            'compinit -d "$HOME/.zcompdump"\n'
            "source $ZSH/oh-my-zsh.sh\n"
            "plugins=(git python zsh-autocomplete)\n"
        )
        self.run_setup()
        self.assertIn("python", self.assert_startup())
        self.assert_idempotent()

    def test_zdotdir_custom_plugins_and_symlinks(self):
        self.config = self.home / "zsh config"
        self.env["ZDOTDIR"] = str(self.config)
        custom = self.home / "custom plugins"
        self.custom.rename(custom)
        self.env["ZSH_CUSTOM"] = str(custom)
        self.config.mkdir()
        target = self.home / "tracked-zshrc"
        target.write_text("plugins=(git)\nsource $ZSH/oh-my-zsh.sh\n")
        (self.config / ".zshrc").symlink_to(target)
        (self.config / ".zshenv").write_text("export KEEP_ME=yes\nskip_global_compinit=0\n")
        self.run_setup()
        self.assertTrue((self.config / ".zshrc").is_symlink())
        self.assertIn("export KEEP_ME=yes", (self.config / ".zshenv").read_text())
        self.assert_startup()
        self.assert_idempotent()

    def test_stale_cache_cleanup_is_scoped(self):
        custom_dump = self.home / ".cache/custom-completion"
        caches = [
            self.home / ".zcompdump", self.home / ".zcompdump-host-5.9",
            self.home / ".cache/zsh/compdump", custom_dump,
        ]
        self.env["ZSH_COMPDUMP"] = str(custom_dump)
        for cache in caches:
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text("stale")
            Path(str(cache) + ".zwc").write_text("compiled")
        unrelated = self.home / ".cache/keep"
        unrelated.write_text("preserve")
        self.run_setup()
        for cache in caches:
            self.assertFalse(cache.exists())
            self.assertFalse(Path(str(cache) + ".zwc").exists())
        self.assertEqual(unrelated.read_text(), "preserve")

    def test_missing_plugin_fails_without_config_changes(self):
        self.write_rc("plugins=(git)\n")
        (self.custom / "plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh").unlink()
        result = self.run_setup(success=False)
        self.assertIn("Run the full setup first", result.stdout)
        self.assertEqual((self.config / ".zshrc").read_text(), "plugins=(git)\n")
        self.assertFalse((self.config / ".zshenv").exists())

    def test_invalid_config_fails_without_overwriting(self):
        original = "if true; then\n"
        self.write_rc(original)
        self.run_setup(success=False)
        self.assertEqual((self.config / ".zshrc").read_text(), original)
        self.assertFalse((self.config / ".zshenv").exists())

    def test_unsupported_dynamic_plugins_fail_explicitly(self):
        original = "plugins=($(choose_plugins) zsh-autocomplete)\n"
        self.write_rc(original)
        result = self.run_setup(success=False)
        self.assertIn("Cannot safely migrate", result.stderr)
        self.assertEqual((self.config / ".zshrc").read_text(), original)

    def test_full_setup_stops_after_failed_migration(self):
        original = "plugins=($(choose_plugins) zsh-autocomplete)\n"
        self.write_rc(original)
        result = self.run_setup(full=True, success=False)
        self.assertIn("Cannot safely migrate", result.stderr)
        self.assertIn(original, (self.config / ".zshrc").read_text())
        self.assertNotIn("# >>> setup_term.sh: completion", (self.config / ".zshrc").read_text())
        self.assertFalse((self.config / ".zshenv").exists())
        self.assertFalse((self.home / ".config/zellij/config.kdl").exists())

    def test_failed_migration_under_phase_error_handler_preserves_files(self):
        original = "plugins=($(choose_plugins) zsh-autocomplete)\n"
        self.write_rc(original)
        result = subprocess.run(
            ["bash", "-c",
             'source "$1" --help >/dev/null; '
             'if ensure_zsh_completion_config; then exit 0; else exit 1; fi',
             "test-phase", str(SCRIPT)],
            env=self.env, text=True, capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cannot safely migrate", result.stderr)
        self.assertEqual((self.config / ".zshrc").read_text(), original)
        self.assertFalse((self.config / ".zshenv").exists())

    def test_compound_compinit_is_not_silently_deleted(self):
        for command in (
            "autoload -Uz compinit && compinit\n",
            "compinit && echo keep-this\n",
            "echo keep-this; compinit\n",
        ):
            with self.subTest(command=command):
                self.write_rc(command)
                result = self.run_setup(success=False)
                self.assertIn("Cannot safely migrate", result.stderr)
                self.assertEqual((self.config / ".zshrc").read_text(), command)

    def test_plugin_append_and_similarly_named_plugin_are_preserved(self):
        self.write_rc(
            "plugins=(git custom-zsh-autocomplete)\n"
            "plugins+=(zsh-autocomplete zsh-autosuggestions python)\n"
            "source $ZSH/oh-my-zsh.sh\n"
        )
        self.run_setup()
        startup = self.assert_startup()
        self.assertIn("custom-zsh-autocomplete", startup)
        self.assertIn("python", startup)
        self.assert_idempotent()

    def test_compound_sources_fail_without_deleting_other_commands(self):
        for suffix in (
            '/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh',
            '/oh-my-zsh.sh',
        ):
            with self.subTest(suffix=suffix):
                original = f'source "$HOME/keep.zsh" && source "$ZSH{suffix}"\n'
                self.write_rc(original)
                self.run_setup(success=False)
                self.assertEqual((self.config / ".zshrc").read_text(), original)

    def test_absolute_oh_my_zsh_source_is_preserved(self):
        source = f'source "{self.home}/.oh-my-zsh/oh-my-zsh.sh"'
        self.write_rc("plugins=(git)\n" + source + "\n")
        self.run_setup()
        self.assertIn(source, (self.config / ".zshrc").read_text())
        self.assert_startup()
        self.assert_idempotent()

    def test_unknown_argument_does_not_install(self):
        result = subprocess.run(
            ["bash", str(SCRIPT), "--not-an-option"],
            env=self.env, text=True, capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unknown option", result.stdout)
        self.assertFalse((self.config / ".zshrc").exists())


if __name__ == "__main__":
    unittest.main()
