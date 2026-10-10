/*
 * Copyright (c) 2012-2026 Daniele Bartolini et al.
 * SPDX-License-Identifier: MIT
 */

#include "export_protocol.h"

#if defined(__linux__)
#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static int socket_address(struct sockaddr_un *addr, const char *path)
{
	size_t len = strlen(path);
	if (len == 0 || len >= sizeof(addr->sun_path))
		return -1;
	memset(addr, 0, sizeof(*addr));
	addr->sun_family = AF_UNIX;
	memcpy(addr->sun_path, path, len + 1);
	return 0;
}

int export_socket_bind(const char *path)
{
	struct sockaddr_un addr;
	if (socket_address(&addr, path) != 0)
		return -1;
	int sock = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	if (sock < 0)
		return -1;
	if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
		close(sock);
		return -1;
	}
	return sock;
}

int export_socket_receive(int sock, CrownExportPacket *packet, int *fd)
{
	char control[CMSG_SPACE(sizeof(int))];
	struct iovec iov = { packet, sizeof(*packet) };
	struct msghdr msg;
	memset(&msg, 0, sizeof(msg));
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;
	msg.msg_control = control;
	msg.msg_controllen = sizeof(control);
	*fd = -1;
	ssize_t size = recvmsg(sock, &msg, MSG_DONTWAIT | MSG_CMSG_CLOEXEC);
	if (size < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
		return 0;
	if (size < 0)
		return -1;
	for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg); cmsg; cmsg = CMSG_NXTHDR(&msg, cmsg)) {
		if (cmsg->cmsg_level == SOL_SOCKET
			&& cmsg->cmsg_type == SCM_RIGHTS
			&& cmsg->cmsg_len >= CMSG_LEN(sizeof(int))
			) {
			memcpy(fd, CMSG_DATA(cmsg), sizeof(int));
			break;
		}
	}
	if (size != sizeof(*packet) || (msg.msg_flags & (MSG_TRUNC | MSG_CTRUNC))
		|| packet->magic != CROWN_EXPORT_MAGIC || packet->version != CROWN_EXPORT_VERSION) {
		if (*fd >= 0)
			close(*fd);
		*fd = -1;
		return -1;
	}
	return 1;
}

int export_socket_send(const char *path, const CrownExportPacket *packet, int fd)
{
	struct sockaddr_un addr;
	if (socket_address(&addr, path) != 0)
		return -1;
	int sock = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	if (sock < 0)
		return -1;
	struct iovec iov = { (void *)packet, sizeof(*packet) };
	struct msghdr msg;
	memset(&msg, 0, sizeof(msg));
	msg.msg_name = &addr;
	msg.msg_namelen = sizeof(addr);
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;
	char control[CMSG_SPACE(sizeof(int))];
	if (fd >= 0) {
		memset(control, 0, sizeof(control));
		msg.msg_control = control;
		msg.msg_controllen = sizeof(control);
		struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
		cmsg->cmsg_level = SOL_SOCKET;
		cmsg->cmsg_type = SCM_RIGHTS;
		cmsg->cmsg_len = CMSG_LEN(sizeof(int));
		memcpy(CMSG_DATA(cmsg), &fd, sizeof(int));
	}
	int result = sendmsg(sock, &msg, MSG_NOSIGNAL);
	close(sock);
	return result == sizeof(*packet) ? 0 : -1;
}

void export_socket_close(int sock, const char *path)
{
	if (sock >= 0)
		close(sock);
	if (path != NULL)
		unlink(path);
}

#else
int export_socket_bind(const char *path)
{
	(void)path;
	return -1;
}

int export_socket_receive(int sock, CrownExportPacket *packet, int *fd)
{
	(void)sock;
	(void)packet;
	*fd = -1;
	return -1;
}

int export_socket_send(const char *path, const CrownExportPacket *packet, int fd)
{
	(void)path;
	(void)packet;
	(void)fd;
	return -1;
}

void export_socket_close(int sock, const char *path)
{
	(void)sock;
	(void)path;
}

#endif /* if defined(__linux__) */
