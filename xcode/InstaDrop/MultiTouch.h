//
//  MultiTouch.h
//  InstaDrop
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

typedef int (*MTContactCallbackFunction)(MTDeviceRef, Finger*, int, double, int);

CFArrayRef MTDeviceCreateList(void); // all multitouch devices (Create rule: caller releases)
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int); // thanks comex

#endif /* MultiTouch_h */