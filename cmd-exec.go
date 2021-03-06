/*
 * Copyright (C) 2017 "IoT.bzh"
 * Author Sebastien Douheret <sebastien@iot.bzh>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/iotbzh/xds-agent/lib/xaapiv1"
	"github.com/urfave/cli"
)

func initCmdExec(cmdDef *[]cli.Command) {
	*cmdDef = append(*cmdDef, cli.Command{
		Name:   "exec",
		Usage:  "execute a command in XDS",
		Action: exec,
		Flags: []cli.Flag{
			cli.StringFlag{
				Name:   "id",
				EnvVar: "XDS_PROJECT_ID",
				Usage:  "project ID you want to build (mandatory variable)",
			},
			cli.StringFlag{
				Name:   "rpath, p",
				EnvVar: "XDS_RPATH",
				Usage:  "relative path into project",
			},
			cli.StringFlag{
				Name:   "sdkid, sdk",
				EnvVar: "XDS_SDK_ID",
				Usage:  "Cross Sdk ID to use to build project",
			},
		},
	})
}

func exec(ctx *cli.Context) error {
	prjID := ctx.String("id")
	rPath := ctx.String("rpath")
	sdkid := ctx.String("sdkid")

	// Check mandatory args
	if prjID == "" {
		return cli.NewExitError("project id must be set (see --id option)", 1)
	}

	argsCommand := make([]string, len(ctx.Args()))
	copy(argsCommand, ctx.Args())
	Log.Infof("Execute: /exec %v", argsCommand)

	// Log useful info for debugging
	ver := xaapiv1.XDSVersion{}
	XdsVersionGet(&ver)
	Log.Infof("XDS version: %v", ver)

	// Process Socket IO events
	type exitResult struct {
		error error
		code  int
	}
	exitChan := make(chan exitResult, 1)

	IOsk.On("disconnection", func(err error) {
		Log.Debugf("WS disconnection event with err: %v\n", err)
		exitChan <- exitResult{err, 2}
	})

	outFunc := func(timestamp, stdout, stderr string) {
		tm := ""
		if ctx.Bool("WithTimestamp") {
			tm = timestamp + "| "
		}
		if stdout != "" {
			fmt.Printf("%s%s", tm, stdout)
		}
		if stderr != "" {
			fmt.Fprintf(os.Stderr, "%s%s", tm, stderr)
		}
	}

	IOsk.On(xaapiv1.ExecOutEvent, func(ev xaapiv1.ExecOutMsg) {
		outFunc(ev.Timestamp, ev.Stdout, ev.Stderr)
	})

	IOsk.On(xaapiv1.ExecExitEvent, func(ev xaapiv1.ExecExitMsg) {
		exitChan <- exitResult{ev.Error, ev.Code}
	})

	IOsk.On(xaapiv1.EVTProjectChange, func(ev xaapiv1.EventMsg) {
		prj, _ := ev.DecodeProjectConfig()
		Log.Infof("Event %v (%v): %v", ev.Type, ev.Time, prj)
	})
	evReg := xaapiv1.EventRegisterArgs{Name: xaapiv1.EVTProjectChange}
	if err := HTTPCli.Post("/events/register", &evReg, nil); err != nil {
		return cli.NewExitError(err, 1)
	}

	// Retrieve the project definition
	prj := xaapiv1.ProjectConfig{}
	if err := HTTPCli.Get("/projects/"+prjID, &prj); err != nil {
		return cli.NewExitError(err, 1)
	}

	// Auto setup rPath if needed
	if rPath == "" {
		cwd, err := os.Getwd()
		if err == nil {
			fldRp := prj.ClientPath
			if !strings.HasPrefix(fldRp, "/") {
				fldRp = "/" + fldRp
			}
			Log.Debugf("Try to auto-setup rPath: cwd=%s ; ClientPath=%s", cwd, fldRp)
			if sp := strings.SplitAfter(cwd, fldRp); len(sp) == 2 {
				rPath = strings.Trim(sp[1], "/")
				Log.Debugf("Auto-setup rPath to: '%s'", rPath)
			}
		}
	}

	// Build env
	Log.Debugf("Command env: %v", EnvConfFileMap)
	env := []string{}
	for k, v := range EnvConfFileMap {
		env = append(env, k+"="+v)
	}

	// Send build command
	args := xaapiv1.ExecArgs{
		ID:         prjID,
		SdkID:      sdkid,
		Cmd:        strings.Trim(argsCommand[0], " "),
		Args:       argsCommand[1:],
		Env:        env,
		RPath:      rPath,
		CmdTimeout: 60,
	}

	LogPost("POST /exec %v", args)
	if err := HTTPCli.Post("/exec", args, nil); err != nil {
		return cli.NewExitError(err.Error(), 1)
	}

	// Wait exit
	select {
	case res := <-exitChan:
		errStr := ""
		if res.code == 0 {
			Log.Debugln("Exit successfully")
		}
		if res.error != nil {
			Log.Debugln("Exit with ERROR: ", res.error.Error())
			errStr = res.error.Error()
		}
		return cli.NewExitError(errStr, res.code)
	}
}
