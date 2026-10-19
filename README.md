# RTEMS 7 in Docker

A Docker image with the RTEMS 7 SPARC cross toolchain and the erc32 BSP,
built from the RTEMS Git main branches. Your application stays on the host
and is mounted into the container. Only the `sparc/erc32` BSP is built, and
applications run in the SIS simulator.

## Requirements

- Docker 23 or newer (BuildKit is required)
- Network access during the image build (Ubuntu mirrors, Docker Hub, gitlab.rtems.org
  and the hosts the RTEMS Source Builder downloads sources from)

## Build the image

    docker build -t rtems7-docker .

The first build compiles the cross toolchain and takes a long time.
Downloads and compiler objects are kept in BuildKit caches, so a failed or
repeated build resumes quickly.

## Run

    docker run --rm -t --init --user "$(id -u):$(id -g)" -v "$PWD/examples/hello:/work" rtems7-docker

This builds `examples/hello/` and runs it in the SIS simulator. The output
ends with `Hello World` and an RTEMS shutdown report, which is expected
because `exit()` shuts down the whole system.

`--user` keeps the build output owned by you. `--init` lets Ctrl-C stop an
application that never exits. Add `--network none` to make sure the build
does not touch the network.

## Commands

Pass a command after the image name:

| Command | Action                                              |
| ------- | --------------------------------------------------- |
| `run`   | Build and run the application (default)             |
| `build` | Build only                                          |
| `shell` | Interactive bash with the application ready to use  |
| `clean` | Remove build output                                 |
| `info`  | Show the RTEMS and rtems_waf commits and GCC version|
| other   | Executed as given, for example `sparc-rtems7-gcc -v`|

The shell needs a terminal:

    docker run --rm -it --init --user "$(id -u):$(id -g)" -v "$PWD/examples/hello:/work" rtems7-docker shell

To run an executable other than `hello.exe`, pass `-e EXE=name.exe` to
`docker run`. To start another application, copy `examples/hello/` and mount the copy instead.

## Layout

    Dockerfile          toolchain, BSP and the rtems-app entrypoint
    .dockerignore       empty build context
    .gitattributes      forces LF line endings
    LICENSE
    examples/hello/     example application
      init.c            RTEMS configuration
      hello.c           Init task
      wscript           Waf build script
      .gitignore

`waf` and `rtems_waf/` are copied from the image into the application on
every run, so they always match the installed RTEMS. They are listed in
`examples/hello/.gitignore`.

## Updating

The image tracks the `main` branches of the RTEMS Source Builder, RTEMS and
rtems_waf. You keep the checkout from the last build until you update.

Refresh RTEMS and the BSP, keeping the toolchain:

    docker build --no-cache-filter bsp -t rtems7-docker .

Rebuild everything (downloads and compiler objects stay cached):

    docker build --pull --no-cache -t rtems7-docker .

Because `main` moves, an update can occasionally fail for reasons unrelated
to this setup. `docker run --rm rtems7-docker info` shows which commits an
image was built from.

## Troubleshooting

- Download errors or checksum failures during the image build: run the same
  command again. The Dockerfile retries source downloads ten times and keeps
  downloaded files in a cache.
- `not writable`: add `--user "$(id -u):$(id -g)"` to the command.
- Stale build errors after an update: run the `clean` command.
- On SELinux hosts, add `:z` to the volume, for example `-v "$PWD/examples/hello:/work:z"`.

## TODO

Planned examples:

- PIC64-HPSC under QEMU: boot a Space Grade Linux image on Microchip's
  PIC64-HPSC emulator, whose SysC firmware is RTEMS based. The Microchip QEMU
  model and SDK are not public and must be requested from Microchip.
  References:
  [meta-sgl build guide](https://github.com/space-grade-linux/meta-sgl/blob/main/docs/building.md),
  [p64h-linux-examples build guide](https://github.com/pic64-hpsc-hx/p64h-linux-examples/blob/p64h_release/docs/building.md)

## License

MIT, see `LICENSE`. The RTEMS tools and sources built into the image keep
their own licenses. The example in `examples/hello/` follows the Hello World
example from the RTEMS Quick Start guide.
