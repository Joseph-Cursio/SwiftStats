//
//  SignalName+ArgumentParser.swift
//  swiftstats
//
//  Lets `swiftstats top` take a signal name as an argument.
//

import ArgumentParser
import SwiftStatsCore

extension SignalName: ExpressibleByArgument {}
