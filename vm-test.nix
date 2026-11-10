{
  pkgs,
  nixpkgs,
  amp-desktop,
}:
pkgs.testers.runNixOSTest {
  name = "amp-desktop";
  requiredFeatures.kvm = false;
  enableOCR = true;

  nodes.machine = {...}: {
    imports = [
      "${nixpkgs}/nixos/tests/common/x11.nix"
      "${nixpkgs}/nixos/tests/common/user-account.nix"
    ];
    test-support.displayManager.auto.user = "alice";
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    environment.stub-ld.enable = false;
    programs.nix-ld.enable = false;
    environment.systemPackages = [
      amp-desktop
      pkgs.desktop-file-utils
      pkgs.xdg-utils
      pkgs.gtk3
      pkgs.xdotool
    ];

    # Only the remote website is replaced. Electron, its sandbox, the desktop
    # launcher and the app's bundled Settings UI are the real installed package.
    services.nginx = {
      enable = true;
      virtualHosts.localhost.locations."/" = {
        extraConfig = "default_type text/html;";
        root = pkgs.writeTextDir "__native/start" ''
          <!doctype html><html><head><title>Amp packaging test</title></head>
          <body><h1>Amp packaging test</h1><p>Electron rendered this page on NixOS.</p></body></html>
        '';
      };
    };
  };

  testScript = ''
    from datetime import timedelta

    start_all()
    machine.wait_for_x()
    machine.wait_for_unit("default.target", "alice")
    machine.succeed("cp /home/alice/.Xauthority /root/.Xauthority")
    machine.succeed("desktop-file-validate ${amp-desktop}/share/applications/amp-desktop.desktop")
    machine.succeed("test ! -e /lib64/ld-linux-x86-64.so.2")
    machine.succeed("su - alice -c 'xdg-mime query default x-scheme-handler/com.ampcode.amp.linux.auth' | grep -x amp-desktop.desktop")
    machine.wait_for_unit("nginx.service")
    machine.succeed("su - alice -c 'DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus AMP_DESKTOP_URL=http://127.0.0.1 gtk-launch amp-desktop > /tmp/amp.log 2>&1' || { cat /tmp/amp.log; exit 1; }")
    try:
        machine.wait_for_window("Amp packaging test", timeout=timedelta(minutes=3))
        machine.wait_for_text("Electron rendered this page on NixOS", timeout=timedelta(minutes=3))
        machine.succeed("pgrep -u alice -f -- --type=renderer")
        machine.succeed("for p in $(pgrep -u alice -f -- --type=renderer); do grep -Eq '^Seccomp:[[:space:]]+2$' /proc/$p/status || exit 1; done")
        machine.screenshot("renderer")
        machine.succeed("xdotool search --name '^Amp packaging test$' windowactivate --sync")
        machine.send_key("alt")
        machine.sleep(timedelta(seconds=2))
        machine.send_key("ret")
        machine.sleep(timedelta(seconds=2))
        machine.send_key("down")
        machine.send_key("ret")
        machine.wait_for_window("Amp Settings", timeout=timedelta(minutes=1))
        machine.wait_for_text("Open at Login", timeout=timedelta(minutes=1))
        machine.screenshot("settings")

        machine.send_key("alt-f4")
        machine.succeed("xprop -id $(xdotool search --name '^Amp packaging test$' | head -1) WM_CLASS | grep -F '\"amp-desktop\", \"amp-desktop\"'")

        # The installed URI handler must reach the existing instance.
        machine.succeed("su - alice -c 'DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus xdg-open \"com.ampcode.amp.linux.auth://open?url=http%3A%2F%2F127.0.0.1%2F__native%2Fstart%3Fcallback%3D1\"'")
        machine.wait_until_succeeds("grep 'GET /__native/start?callback=1 ' /var/log/nginx/access.log", timeout=timedelta(minutes=1))
        assert machine.succeed("xdotool search --onlyvisible --name '^Amp packaging test$' | wc -l").strip() == "1"
        machine.screenshot("uri")
    finally:
        print(machine.execute("cat /tmp/amp.log"))
  '';
}
