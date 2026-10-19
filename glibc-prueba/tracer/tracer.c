// Mini rastreador: ejecuta un programa bajo ptrace (siguiendo a sus hijos) y,
// cuando seccomp lo mataría con SIGSYS, anota la syscall bloqueada y la hace
// fallar con -ENOSYS para que glibc pruebe su alternativa.
#include <elf.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>
#include <asm/ptrace.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "uso: %s programa [args...]\n", argv[0]);
        return 2;
    }
    pid_t child = fork();
    if (child == 0) {
        ptrace(PTRACE_TRACEME, 0, 0, 0);
        raise(SIGSTOP);
        execv(argv[1], argv + 1);
        perror("execv");
        _exit(127);
    }

    int status;
    waitpid(child, &status, 0);
    ptrace(PTRACE_SETOPTIONS, child, 0,
           PTRACE_O_TRACEFORK | PTRACE_O_TRACEVFORK | PTRACE_O_TRACECLONE |
           PTRACE_O_TRACEEXEC | PTRACE_O_EXITKILL);
    ptrace(PTRACE_CONT, child, 0, 0);

    int exit_code = 0;
    for (;;) {
        pid_t pid = waitpid(-1, &status, __WALL);
        if (pid < 0) break;
        if (WIFEXITED(status) || WIFSIGNALED(status)) {
            if (pid == child) exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
            continue;
        }
        if (!WIFSTOPPED(status)) continue;

        int sig = WSTOPSIG(status);
        int event = status >> 16;
        int deliver = 0;
        if (event != 0) {
            // fork/clone/exec: los hijos quedan rastreados automáticamente.
        } else if (sig == SIGSYS) {
            siginfo_t si;
            ptrace(PTRACE_GETSIGINFO, pid, 0, &si);
            struct user_pt_regs regs;
            struct iovec io = {&regs, sizeof(regs)};
            ptrace(PTRACE_GETREGSET, pid, (void *)NT_PRSTATUS, &io);
            fprintf(stderr, "[tracer] pid %d: syscall bloqueada nr=%d -> ENOSYS\n", pid, si.si_syscall);
            regs.regs[0] = (unsigned long long)-ENOSYS;
            ptrace(PTRACE_SETREGSET, pid, (void *)NT_PRSTATUS, &io);
        } else if (sig == SIGSTOP || sig == SIGTRAP) {
            // parada inicial de hijos nuevos
        } else {
            deliver = sig;
        }
        ptrace(PTRACE_CONT, pid, 0, deliver);
    }
    return exit_code;
}
