"""Persistent Chrome profile + skip-login support (custom fork addition).

Two opt-in behaviours, both driven by settings.json and wired into
`nodriver_tixcraft.py` with a few import lines (minimal-diff policy, see CLAUDE.md):

1. Persistent profile -- upstream `nodriver_common.get_extension_config()` always
   lets zendriver create a fresh temp `user_data_dir` per launch, so cookies /
   login sessions are discarded on every restart. Enable a fixed profile dir so
   you stay logged in across runs:

       "advanced": { "persistent_profile": true }     # uses src/chrome_profile
       // or a custom path:
       // "advanced": { "persistent_profile": "/abs/path/to/profile" }

2. Skip KKTIX sign_in redirect -- upstream `nodriver_goto_homepage()` force-routes
   the browser to kktix.com/users/sign_in at startup whenever a kktix account is
   configured. When you already carry a logged-in session (persistent profile),
   that detour is unnecessary; this makes the bot park straight on the event page.

   Defaults to following `persistent_profile`. Override explicitly with:

       "advanced": { "skip_kktix_signin": true }   // or false to force the redirect

Usage: turn on `persistent_profile`, launch once, log in to KKTIX manually, close.
Every later run starts already logged in and waits directly on the event page.

Caveat: a fixed profile can only be opened by ONE Chrome at a time. Close any bot
window using this profile before launching again, or the launch will fail.
"""

import asyncio
import os
import random

import nodriver_common
import util

_DEFAULT_PROFILE_DIRNAME = "chrome_profile"

_original_get_extension_config = nodriver_common.get_extension_config


def _resolve_profile_dir(config_dict):
    """Return an absolute profile path if persistence is enabled, else None."""
    try:
        setting = config_dict.get("advanced", {}).get("persistent_profile", False)
    except AttributeError:
        return None

    if not setting:
        return None

    if isinstance(setting, str) and setting.strip():
        path = os.path.expanduser(setting.strip())
        if not os.path.isabs(path):
            path = os.path.join(util.get_app_root(), path)
        return path

    # Truthy non-string (e.g. True) -> default location under src/
    return os.path.join(util.get_app_root(), _DEFAULT_PROFILE_DIRNAME)


def get_extension_config(config_dict, args=None):
    conf = _original_get_extension_config(config_dict, args)

    profile_dir = _resolve_profile_dir(config_dict)
    if profile_dir:
        # MCP connect mode returns a Config that attaches to an existing browser
        # (host/port set); injecting a data dir there is meaningless, so skip it.
        mcp_connect = bool(args and getattr(args, "mcp_connect", None))
        if not mcp_connect:
            debug = util.create_debug_logger(config_dict)
            os.makedirs(profile_dir, exist_ok=True)
            conf.user_data_dir = profile_dir
            debug.log(f"[PROFILE] Using persistent Chrome profile: {profile_dir}")
            # A fixed profile can only be opened by one Chrome at a time; a leftover
            # lock means another instance is still using it (launch will fail).
            if os.path.exists(os.path.join(profile_dir, "SingletonLock")):
                debug.log(
                    "[PROFILE] WARNING: SingletonLock present -- another Chrome may "
                    "be using this profile. Close it before launching."
                )

    return conf


# Activate the get_extension_config patch on import.
nodriver_common.get_extension_config = get_extension_config


def _should_skip_kktix_signin(config_dict):
    """Whether to bypass the forced KKTIX sign_in redirect at startup.

    Explicit `skip_kktix_signin` wins; otherwise follows `persistent_profile`
    (a logged-in persistent session makes the redirect pointless).
    """
    try:
        adv = config_dict.get("advanced", {})
    except AttributeError:
        return False
    explicit = adv.get("skip_kktix_signin", None)
    if explicit is not None:
        return bool(explicit)
    return bool(adv.get("persistent_profile"))


_homepage_patch_installed = False


def install_homepage_patch(module):
    """Wrap `module.nodriver_goto_homepage` to optionally skip the KKTIX sign_in
    redirect. Called from nodriver_tixcraft after that function is defined
    (it does not exist yet when this module is first imported)."""
    global _homepage_patch_installed
    if _homepage_patch_installed:
        return
    original_goto = getattr(module, "nodriver_goto_homepage", None)
    if original_goto is None:
        return

    async def nodriver_goto_homepage(driver, config_dict):
        homepage = config_dict.get("homepage", "")
        if "kktix.c" in homepage and _should_skip_kktix_signin(config_dict):
            debug = util.create_debug_logger(config_dict)
            debug.log("[PROFILE] Skipping KKTIX sign_in redirect; parking on event page")
            tab = None
            try:
                tab = await driver.get(homepage)
                await asyncio.sleep(random.uniform(1.0, 2.5))
            except Exception as e:
                debug.log(f"[PROFILE] Failed to navigate to kktix homepage: {e}")
            return tab
        return await original_goto(driver, config_dict)

    module.nodriver_goto_homepage = nodriver_goto_homepage
    _homepage_patch_installed = True
