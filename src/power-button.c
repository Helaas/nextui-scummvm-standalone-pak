/*
 * power-button: power key handling for platforms minui-power-control does not
 * cover (h700, where its handler listens on the pad's input node).
 *
 * Watches the input device that reports KEY_POWER. A short press stops the
 * emulator, runs NextUI's $SYSTEM_PATH/bin/suspend (which returns after wake)
 * and resumes it; holding the key for 2 seconds stops the emulator and asks
 * NextUI's launch loop to power off via /tmp/poweroff, the same as
 * minui-power-control's NextUI path. Exits when the emulator exits.
 *
 * H700's ALSA driver does not recover a PCM left open across suspend, so with
 * SCUMMVM_AUDIO_SIGNALS set the helper sends SIGUSR1 (ScummVM closes its audio
 * device, via the pak's patch) and waits for the PCM to close before sleeping,
 * then SIGUSR2 after wake to reopen it. The suspend script runs with
 * NEXTUI_LD_LIBRARY_PATH, so services it restarts don't load the pak's lib/.
 *
 * usage: power-button <emulator-process-name>
 * POWER_BUTTON_DRY_RUN=1 logs the actions instead of performing them.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define HOLD_MS 2000
#define COOLDOWN_MS 1000
#define BITS_PER_LONG (sizeof(long) * 8)

static int dry_run;
static int audio_signals;

static void logmsg(const char *fmt, ...) {
	char stamp[32];
	time_t t = time(NULL);
	struct tm tm;
	va_list ap;

	localtime_r(&t, &tm);
	strftime(stamp, sizeof(stamp), "%Y/%m/%d %H:%M:%S", &tm);
	printf("%s power-button: ", stamp);
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	putchar('\n');
	fflush(stdout);
}

/* Monotonic time stops during suspend, so a wake does not look like a hold. */
static long long now_ms(void) {
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
}

static pid_t find_process(const char *name) {
	DIR *proc = opendir("/proc");
	struct dirent *entry;
	pid_t found = 0;

	if (!proc)
		return 0;
	while (!found && (entry = readdir(proc))) {
		char path[64], comm[32];
		pid_t pid = (pid_t)atoi(entry->d_name);
		FILE *f;

		if (pid <= 0 || pid == getpid())
			continue;
		snprintf(path, sizeof(path), "/proc/%d/comm", pid);
		f = fopen(path, "r");
		if (!f)
			continue;
		if (fgets(comm, sizeof(comm), f)) {
			comm[strcspn(comm, "\n")] = '\0';
			if (strcmp(comm, name) == 0)
				found = pid;
		}
		fclose(f);
	}
	closedir(proc);
	return found;
}

static int reports_power_key(int fd) {
	unsigned long bits[KEY_MAX / BITS_PER_LONG + 1];

	memset(bits, 0, sizeof(bits));
	if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) < 0)
		return 0;
	return (bits[KEY_POWER / BITS_PER_LONG] >> (KEY_POWER % BITS_PER_LONG)) & 1;
}

static int open_power_device(char *path, size_t size) {
	for (int i = 0; i < 64; i++) {
		int fd;

		snprintf(path, size, "/dev/input/event%d", i);
		fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		if (reports_power_key(fd))
			return fd;
		close(fd);
	}
	return -1;
}

static void drain(int fd) {
	struct input_event ev;

	while (read(fd, &ev, sizeof(ev)) == sizeof(ev))
		;
}

/* True while the process holds an ALSA playback PCM open. */
static int holds_playback_pcm(pid_t pid) {
	char dir_path[64];
	DIR *dir;
	struct dirent *entry;
	int found = 0;

	snprintf(dir_path, sizeof(dir_path), "/proc/%d/fd", pid);
	dir = opendir(dir_path);
	if (!dir)
		return 0;
	while (!found && (entry = readdir(dir))) {
		char link_path[sizeof(dir_path) + sizeof(entry->d_name) + 1], target[128];
		ssize_t len;

		if (entry->d_name[0] == '.')
			continue;
		snprintf(link_path, sizeof(link_path), "%s/%s", dir_path, entry->d_name);
		len = readlink(link_path, target, sizeof(target) - 1);
		if (len <= 0)
			continue;
		target[len] = '\0';
		if (strncmp(target, "/dev/snd/pcmC", 13) == 0 && target[len - 1] == 'p')
			found = 1;
	}
	closedir(dir);
	return found;
}

static void close_emulator_audio(pid_t emulator) {
	kill(emulator, SIGUSR1);
	for (int i = 0; i < 20 && holds_playback_pcm(emulator); i++)
		usleep(100000);
	if (holds_playback_pcm(emulator))
		logmsg("Audio device still open after 2 s; suspending anyway");
}

static void suspend_system(pid_t emulator) {
	const char *system_path = getenv("SYSTEM_PATH");
	char script[512];
	pid_t child;
	int status;

	if (!system_path || !*system_path) {
		logmsg("SYSTEM_PATH is not set; cannot suspend");
		return;
	}
	snprintf(script, sizeof(script), "%s/bin/suspend", system_path);
	if (access(script, R_OK) != 0) {
		logmsg("Suspend script %s not found", script);
		return;
	}
	if (dry_run) {
		logmsg("[dry run] would stop pid %d%s, run %s, resume pid %d", emulator,
		       audio_signals ? " after closing its audio" : "", script, emulator);
		return;
	}

	if (audio_signals)
		close_emulator_audio(emulator);
	kill(emulator, SIGSTOP);
	child = fork();
	if (child == 0) {
		const char *system_libs = getenv("NEXTUI_LD_LIBRARY_PATH");

		if (system_libs)
			setenv("LD_LIBRARY_PATH", system_libs, 1);
		execl("/bin/sh", "sh", script, (char *)NULL);
		_exit(127);
	}
	if (child > 0)
		waitpid(child, &status, 0);
	kill(emulator, SIGCONT);
	if (audio_signals)
		kill(emulator, SIGUSR2);
	logmsg("Resumed from suspend");
}

static void shutdown_system(pid_t emulator) {
	int fd;

	if (dry_run) {
		logmsg("[dry run] would create /tmp/poweroff and terminate pid %d", emulator);
		return;
	}

	sync();
	fd = open("/tmp/poweroff", O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
	if (fd >= 0)
		close(fd);
	kill(emulator, SIGCONT);
	kill(emulator, SIGTERM);
	for (int i = 0; i < 50 && kill(emulator, 0) == 0; i++)
		usleep(100000);
	if (kill(emulator, 0) == 0)
		kill(emulator, SIGKILL);
	sync();
	exit(0);
}

int main(int argc, char **argv) {
	char path[64];
	struct pollfd pfd;
	long long press_ms = 0, cooldown_until = 0;
	int hold_handled = 0;
	pid_t emulator = 0;
	const char *dry = getenv("POWER_BUTTON_DRY_RUN");
	const char *audio = getenv("SCUMMVM_AUDIO_SIGNALS");

	if (argc != 2) {
		fprintf(stderr, "usage: %s <emulator-process-name>\n", argv[0]);
		return 2;
	}
	dry_run = dry && *dry && *dry != '0';
	audio_signals = audio && *audio && *audio != '0';

	for (int i = 0; i < 10 && !(emulator = find_process(argv[1])); i++) {
		logmsg("Waiting for %s to start...", argv[1]);
		sleep(1);
	}
	if (!emulator) {
		logmsg("Emulator process %s not found", argv[1]);
		return 1;
	}

	pfd.fd = open_power_device(path, sizeof(path));
	if (pfd.fd < 0) {
		logmsg("No input device reports KEY_POWER");
		return 1;
	}
	pfd.events = POLLIN;
	logmsg("Listening on %s for %s (pid %d)%s", path, argv[1], emulator, dry_run ? " [dry run]" : "");

	while (kill(emulator, 0) == 0 || errno != ESRCH) {
		int ready = poll(&pfd, 1, 100);
		struct input_event ev;

		if (press_ms && !hold_handled && now_ms() - press_ms >= HOLD_MS) {
			hold_handled = 1;
			logmsg("Button held for 2 seconds, shutting down...");
			shutdown_system(emulator);
		}
		if (ready <= 0)
			continue;

		while (read(pfd.fd, &ev, sizeof(ev)) == sizeof(ev)) {
			if (ev.type != EV_KEY || ev.code != KEY_POWER)
				continue;
			if (now_ms() < cooldown_until) {
				press_ms = 0;
				continue;
			}
			if (ev.value == 1) {
				press_ms = now_ms();
				hold_handled = 0;
			} else if (ev.value == 0 && press_ms) {
				int short_press = !hold_handled && now_ms() - press_ms < HOLD_MS;

				press_ms = 0;
				hold_handled = 0;
				if (short_press) {
					logmsg("Short press detected, suspending...");
					suspend_system(emulator);
					drain(pfd.fd);
					cooldown_until = now_ms() + COOLDOWN_MS;
					break;
				}
			}
		}
	}

	logmsg("%s exited", argv[1]);
	return 0;
}
