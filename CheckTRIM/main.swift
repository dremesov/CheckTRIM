//
//  main.swift
//  CheckTRIM
//
//  Created by Dmitry Remesov on 29.11.14.
//  Copyright (c) 2014 Dmitry Remesov. All rights reserved.
//

import Foundation

func isTRIMSupported() -> Bool {
	var taskout = NSPipe()
	var sptask = NSTask()
	sptask.standardOutput = taskout
	sptask.launchPath = "/usr/sbin/system_profiler"
	sptask.arguments = ["-xml", "SPSerialATADataType"]
	sptask.launch()
	sptask.waitUntilExit()
	if sptask.terminationStatus == 0 {
		var err : NSError?
		let pl: AnyObject? = NSPropertyListSerialization.propertyListWithData(taskout.fileHandleForReading.readDataToEndOfFile(), options: NSPropertyListReadOptions(0), format: nil, error: &err)
		if (pl? is NSArray && pl?.count == 1 &&
			pl?[0] is NSDictionary &&
			pl?[0]["_items"] is NSArray &&
			(pl?[0]["_items"] as NSArray)[0] is NSDictionary &&
			(pl?[0]["_items"] as NSArray)[0]["_items"] is NSArray &&
			((pl?[0]["_items"] as NSArray)[0]["_items"] as NSArray)[0] is NSDictionary) {

				let p = ((pl?[0]["_items"] as NSArray)[0]["_items"] as NSArray)[0] as NSDictionary
				if (p["spsata_medium_type"] as String) == "Solid State" &&
					(p["spsata_trim_support"] as String) == "Yes" {
						return true
				}
		}
	}
	return false
}

func turnTRIMon() -> Bool {
	println("TRIM is off, trying to patch")
	let kext_path = "/System/Library/Extensions/IOAHCIFamily.kext/Contents/PlugIns/IOAHCIBlockStorage.kext/Contents/MacOS/IOAHCIBlockStorage"
	if var kext = NSMutableData(contentsOfFile: kext_path) {
		let mark = ("kIOPMResetPowerStateOnWakeKey\n", "APPLE SSD", "Time To Ready")
		let marklen = (
			mark.0.lengthOfBytesUsingEncoding(NSASCIIStringEncoding),
			mark.1.lengthOfBytesUsingEncoding(NSASCIIStringEncoding),
			mark.2.lengthOfBytesUsingEncoding(NSASCIIStringEncoding)
		)
		var ptr = memmem(kext.bytes, UInt(kext.length), mark.0, UInt(marklen.0))
		if ptr != nil {
			println("found \(mark.0) at \(ptr)")
			ptr += marklen.0
			while UnsafeMutablePointer<Int8>(++ptr).memory == 0 {}
			if memcmp(ptr, mark.1, UInt(marklen.1)) == 0 {
				let offset = UnsafePointer<Void>(ptr) - kext.bytes
				println("found \(mark.1) at \(ptr) (offset: \(offset))")
				ptr += marklen.1
				while UnsafeMutablePointer<Int8>(++ptr).memory == 0 {}
				if memcmp(ptr, mark.2, UInt(marklen.2)) == 0 {
					println("found \(mark.2) at \(ptr), patching...")
					kext.resetBytesInRange(NSRange(location: offset, length: marklen.1))
					var err : NSError?
					let fm = NSFileManager.defaultManager()
					let kext_orig = kext_path.stringByAppendingPathExtension("orig")!

					if fm.fileExistsAtPath(kext_orig) {
						fm.removeItemAtPath(kext_orig, error: nil);
					}

					fm.moveItemAtPath(kext_path, toPath: kext_orig, error: &err)

					if err != nil {
						println("error renaming file: \(err?.localizedFailureReason!)")
					} else {
						kext.writeToFile(kext_path, atomically: false)
						fm.setAttributes([NSFilePosixPermissions : NSNumber(short: 0o755)], ofItemAtPath: kext_path, error: &err)
						if err != nil {
							println("error setting attributes of file: \(err?.localizedFailureReason!)")
							fm.removeItemAtPath(kext_path, error: nil)
							fm.moveItemAtPath(kext_orig, toPath: kext_path, error: nil)
						} else {
							fm.setAttributes([NSFileModificationDate: NSDate()], ofItemAtPath: "/System/Library/Extensions", error: nil)
							return true
						}
					}
				}
			}
		}
	}
	println("Not found markers to patch where expected")
	return false
}

if !isTRIMSupported() {
	exit(turnTRIMon() ? 0 : 1)
} else {
	println("TRIM is on or could not retrieve information from system_profiler")
}
