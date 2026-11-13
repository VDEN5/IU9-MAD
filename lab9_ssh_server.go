package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/gliderlabs/ssh"
	"github.com/pkg/sftp"
	"golang.org/x/term"
)

const (
	Username = "root"
	Password = "123"
)

var (
	cwdMap     = sync.Map{}
	defaultCwd = "/root"
)

func init() {
	if wd, err := os.Getwd(); err == nil {
		defaultCwd = wd
	}
}

func getCwd(key string) string {
	if v, ok := cwdMap.Load(key); ok {
		if s, ok := v.(string); ok && s != "" {
			return s
		}
	}
	return defaultCwd
}

func setCwd(key, dir string) { cwdMap.Store(key, dir) }

func resolveCd(cwd, target string) (string, error) {
	if target == "" || target == "~" {
		return "/root", nil
	}
	if !strings.HasPrefix(target, "/") {
		target = filepath.Join(cwd, target)
	}
	target = filepath.Clean(target)
	info, err := os.Stat(target)
	if err != nil || !info.IsDir() {
		return "", fmt.Errorf("cd: %s: No such file or directory", target)
	}
	return target, nil
}

func runShell(w io.Writer, cwd, command string) {
	c := exec.Command("/bin/bash", "-c", command)
	c.Dir = cwd
	c.Stdout = w
	c.Stderr = w
	c.Env = append(os.Environ(), "TERM=dumb")
	_ = c.Run()
}

func handleExec(w io.Writer, key, cwd, command string) string {
	trimmed := strings.TrimSpace(command)

	if trimmed == "cd" || strings.HasPrefix(trimmed, "cd ") {
		target := ""
		if trimmed != "cd" {
			target = strings.TrimSpace(strings.TrimPrefix(trimmed, "cd"))
		}
		newCwd, err := resolveCd(cwd, target)
		if err != nil {
			fmt.Fprintln(w, err.Error())
			return cwd
		}
		setCwd(key, newCwd)
		return newCwd
	}

	runShell(w, cwd, command)
	return cwd
}

func SftpHandler(sess ssh.Session) {
	server, err := sftp.NewServer(sess)
	if err != nil {
		log.Printf("sftp server init error: %s\n", err)
		return
	}
	if err := server.Serve(); err == io.EOF {
		server.Close()
		fmt.Println("sftp client exited session.")
	} else if err != nil {
		fmt.Println("sftp server completed with error:", err)
	}
}

func SSHSessionHandler(sess ssh.Session) {
	key := sess.RemoteAddr().String()
	cwd := getCwd(key)

	if cmd := sess.Command(); len(cmd) > 0 {
		handleExec(sess, key, cwd, strings.Join(cmd, " "))
		return
	}

	io.WriteString(sess, "Welcome to the SSH server!\n")
	t := term.NewTerminal(sess, "> ")
	for {
		line, err := t.ReadLine()
		if err != nil {
			if err == io.EOF {
				log.Printf("Terminal closed/EOF")
				break
			}
			log.Printf("Error reading from terminal: %s\n", err)
			continue
		}
		if strings.TrimSpace(line) == "" {
			continue
		}
		cwd = handleExec(sess, key, cwd, line)
	}
}

func main() {
	sshHandler := ssh.Server{
		Addr: "0.0.0.0:9092",
		SubsystemHandlers: map[string]ssh.SubsystemHandler{
			"sftp": SftpHandler,
		},
		Handler: SSHSessionHandler,
		PasswordHandler: func(ctx ssh.Context, pass string) bool {
			return ctx.User() == Username && pass == Password
		},
	}

	log.Println("SSH server listening on :9092, default cwd:", defaultCwd)
	log.Fatal(sshHandler.ListenAndServe())
}