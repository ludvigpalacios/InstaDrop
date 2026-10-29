//
//  MultiTouch.h
//  No drag release delay
//
//  Created by Pravdomil Toman on 16/12/2017.
//  Copyright © 2017 Pravdomil Toman. All rights reserved.
//

#ifndef MultiTouch_h
#define MultiTouch_h

#import <CoreFoundation/CoreFoundation.h>

// https://github.com/jnordberg/FingerMgmt/blob/master/FingerMgmt/MultiTouch.h

typedef struct { float x,y; } mtPoint;
typedef struct { mtPoint pos,vel; } mtReadout;

typedef struct {
    int frame;
    double timestamp;
    int identifier, state, foo3, foo4;
    mtReadout normalized;
    float size;
    int zero1;
    float angle, majorAxis, minorAxis; // ellipsoid
    mtReadout mm;
    int zero2[2];
    float unk2;
} Finger;

typedef void *MTDeviceRef;

// The first argument is a device pointer, so it must be declared as one
// (it was `int` before, which is wrong on 64-bit and sloppy on arm64).
typedef int (*MTContactCallbackFunction)(MTDeviceRef, Finger*, int, double, int);

MTDeviceRef MTDeviceCreateDefault(void);
CFArrayRef MTDeviceCreateList(void); // all multitouch devices (Create rule: caller releases)
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int); // thanks comex
int MTDeviceGetVersion(MTDeviceRef, int);

#endif /* MultiTouch_h */
