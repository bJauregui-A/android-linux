# DDX de Android (B11): parte de hw/vfb. Se compila como biblioteca, no como ejecutable.
srcs = [
    'InitInput.c',
    'InitOutput.c',
    'jni.c',
    '../../mi/miinitext.c',
    '../../mi/miinitext.h',
]

xandroid_server = shared_library(
    'xserver',
    srcs,
    include_directories: inc,
    dependencies: [common_dep, dependency('', required: false)],
    link_args: ['-llog', '-landroid'],
    link_with: [
        libxserver_main,
        libxserver_fb,
        libxserver,
        libxserver_xkb_stubs,
        libxserver_xi_stubs,
    ],
    install: true,
)
