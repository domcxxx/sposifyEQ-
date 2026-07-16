
// SpotifyEQ10 - 10-band equalizer for Spotify with Custom dB range & Visual Labels
// Pure ObjC runtime swizzling

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define CUSTOM_BAND_COUNT 10

// ============================================
// MARK: - Custom Tuning Configuration
// ============================================
#define MAX_DB 24.0                     // Apple's hardware limit is 24.0dB
#define MULTIPLIER (MAX_DB / 12.0)      // Scale factor (24dB / 12 = 2.0x range)

static char dbLabelKey;

// ============================================
// MARK: - UI Helper Functions
// ============================================

// Detects if the current slider is inside the Spotify Equalizer interface
static BOOL isEqualizerSlider(UISlider *slider) {
    if (!slider) return NO;
    UIResponder *responder = slider;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            NSString *className = NSStringFromClass([responder class]);
            if ([className rangeOfString:@"Equalizer" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return YES;
            }
        }
        responder = [responder nextResponder];
    }
    return NO;
}

// Renders and updates the floating text label directly on top of the slider knob
static void updateDbLabel(UISlider *self) {
    UILabel *label = objc_getAssociatedObject(self, &dbLabelKey);
    if (!label) {
        label = [[UILabel alloc] init];
        label.font = [UIFont boldSystemFontOfSize:9];
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        
        // Add text shadow for maximum readability on varying backgrounds
        label.layer.shadowColor = [UIColor blackColor].CGColor;
        label.layer.shadowOffset = CGSizeMake(0, 1);
        label.layer.shadowRadius = 1.0;
        label.layer.shadowOpacity = 0.8;
        label.layer.masksToBounds = NO;
        
        // Equalizer views rotate sliders by 90 degrees.
        // We invert the transform so our text stays perfectly upright.
        if (!CGAffineTransformIsIdentity(self.transform)) {
            label.transform = CGAffineTransformInvert(self.transform);
        }
        
        [self addSubview:label];
        objc_setAssociatedObject(self, &dbLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    // Convert current slider position back to readable dB scale
    float dbVal = self.value * 12.0;
    label.text = [NSString stringWithFormat:@"%.1fdB", dbVal];
    
    // Position the label dynamically over the center of the slider thumb
    CGRect trackRect = [self trackRectForBounds:self.bounds];
    CGRect thumbRect = [self thumbRectForBounds:self.bounds trackRect:trackRect value:self.value];
    
    label.bounds = CGRectMake(0, 0, 40, 15);
    label.center = CGPointMake(CGRectGetMidX(thumbRect), CGRectGetMidY(thumbRect));
}

// ============================================
// MARK: - Helper to expand array to 10 values
// ============================================

static NSArray* expandTo10(NSArray *input) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:CUSTOM_BAND_COUNT];
    for (NSUInteger i = 0; i < CUSTOM_BAND_COUNT; i++) {
        if (input && i < input.count) {
            [result addObject:input[i]];
        } else {
            [result addObject:@(0.0)];
        }
    }
    return [result copy];
}

// ============================================
// MARK: - Direct ivar manipulation
// ============================================

static void expandArrayIvar(id model, const char *ivarName, int targetCount) {
    if (!model) return;
    
    Class cls = [model class];
    Ivar ivar = class_getInstanceVariable(cls, ivarName);
    
    if (ivar) {
        NSArray *currentArray = object_getIvar(model, ivar);
        NSLog(@"[SpotifyEQ10] Found %s ivar, current count: %lu", ivarName, (unsigned long)currentArray.count);
        
        if (currentArray && currentArray.count < targetCount) {
            NSMutableArray *expanded = [NSMutableArray arrayWithArray:currentArray];
            
            while (expanded.count < targetCount) {
                [expanded addObject:@(0.0)];
            }
            
            NSArray *newArray = [expanded copy];
            object_setIvar(model, ivar, newArray);
            NSLog(@"[SpotifyEQ10] Expanded %s to %lu elements", ivarName, (unsigned long)newArray.count);
        }
    } else {
        NSLog(@"[SpotifyEQ10] Ivar %s not found", ivarName);
    }
}

// ============================================
// MARK: - Original IMP storage  
// ============================================

static IMP orig_setValues = NULL;
static IMP orig_values = NULL;
static IMP orig_initWithLocalSettings = NULL;
static IMP orig_bands = NULL;

static IMP orig_sliderLayoutSubviews = NULL;
static IMP orig_sliderSetValueAnimated = NULL;

// ============================================
// MARK: - Replacement implementations
// ============================================

// Hooking UISlider Layout
static void new_sliderLayoutSubviews(UISlider *self, SEL _cmd) {
    if (orig_sliderLayoutSubviews) {
        ((void(*)(id,SEL))orig_sliderLayoutSubviews)(self, _cmd);
    }
    
    if (isEqualizerSlider(self)) {
        // Enforce our custom max and min slider boundaries
        if (self.minimumValue != -MULTIPLIER) {
            self.minimumValue = -MULTIPLIER;
        }
        if (self.maximumValue != MULTIPLIER) {
            self.maximumValue = MULTIPLIER;
        }
        updateDbLabel(self);
    }
}

// Hooking UISlider Value Change Events
static void new_sliderSetValueAnimated(UISlider *self, SEL _cmd, float value, BOOL animated) {
    if (orig_sliderSetValueAnimated) {
        ((void(*)(id,SEL,float,BOOL))orig_sliderSetValueAnimated)(self, _cmd, value, animated);
    }
    
    if (isEqualizerSlider(self)) {
        updateDbLabel(self);
    }
}

// SPTEqualizerModel setValues:
static void new_setValues(id self, SEL _cmd, NSArray *values) {
    NSLog(@"[SpotifyEQ10] setValues: input count=%lu", (unsigned long)values.count);
    
    NSArray *expanded = expandTo10(values);
    NSLog(@"[SpotifyEQ10] setValues: expanded to %lu", (unsigned long)expanded.count);
    
    if (orig_setValues) {
        ((void(*)(id,SEL,NSArray*))orig_setValues)(self, _cmd, expanded);
    }
    
    expandArrayIvar(self, "_values", CUSTOM_BAND_COUNT);
}

// SPTEqualizerModel values
static NSArray* new_values(id self, SEL _cmd) {
    Class cls = [self class];
    Ivar ivar = class_getInstanceVariable(cls, "_values");
    
    NSArray *result = nil;
    if (ivar) {
        result = object_getIvar(self, ivar);
    }
    
    if (!result && orig_values) {
        result = ((NSArray*(*)(id,SEL))orig_values)(self, _cmd);
    }
    
    if (!result || result.count < CUSTOM_BAND_COUNT) {
        result = expandTo10(result);
        if (ivar) {
            object_setIvar(self, ivar, result);
        }
    }
    
    NSLog(@"[SpotifyEQ10] values: returning %lu items", (unsigned long)result.count);
    return result;
}

static NSArray* getStandardFrequencies(void) {
    return @[@(31), @(63), @(125), @(250), @(500), @(1000), @(2000), @(4000), @(8000), @(16000)];
}

static BOOL bandsDumped = NO;

// SPTEqualizerModel bands
static NSArray* new_bands(id self, SEL _cmd) {
    Class cls = [self class];
    Ivar ivar = class_getInstanceVariable(cls, "_bands");
    
    NSArray *result = nil;
    if (ivar) {
        result = object_getIvar(self, ivar);
    }
    
    if (!result && orig_bands) {
        result = ((NSArray*(*)(id,SEL))orig_bands)(self, _cmd);
    }
    
    if (!bandsDumped && result.count > 0) {
        bandsDumped = YES;
        NSLog(@"[SpotifyEQ10] ========== ORIGINAL BANDS ==========");
        NSLog(@"[SpotifyEQ10] Class: %@", NSStringFromClass([result[0] class]));
        NSLog(@"[SpotifyEQ10] Values: %@", result);
        NSLog(@"[SpotifyEQ10] =====================================");
    }
    
    NSArray *frequencies = getStandardFrequencies();
    if (ivar) {
        object_setIvar(self, ivar, frequencies);
    }
    
    NSLog(@"[SpotifyEQ10] bands: returning 10 frequencies");
    return frequencies;
}

// SPTEqualizerModel init methods
static id new_initWithLocalSettings(id self, SEL _cmd, id settings, id driver, id manager, id props, id prefs) {
    NSLog(@"[SpotifyEQ10] initWithLocalSettings called");
    
    id result = nil;
    if (orig_initWithLocalSettings) {
        result = ((id(*)(id,SEL,id,id,id,id,id))orig_initWithLocalSettings)(self, _cmd, settings, driver, manager, props, prefs);
    }
    
    if (result) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            expandArrayIvar(result, "_values", CUSTOM_BAND_COUNT);
            if ([result respondsToSelector:@selector(bands)]) {
                NSLog(@"[SpotifyEQ10] Forcing bands() call");
                [result performSelector:@selector(bands)];
            }
        });
    }
    
    return result;
}

// ============================================
// MARK: - Hook installer
// ============================================

static void installHook(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    if (!cls) return;
    
    Method method = class_getInstanceMethod(cls, sel);
    if (method) {
        *origImp = method_setImplementation(method, newImp);
        NSLog(@"[SpotifyEQ10] Hooked %@.%@", NSStringFromClass(cls), NSStringFromSelector(sel));
    } else {
        NSLog(@"[SpotifyEQ10] Method not found: %@.%@", NSStringFromClass(cls), NSStringFromSelector(sel));
    }
}

// ============================================
// MARK: - Constructor
// ============================================

__attribute__((constructor))
static void init(void) {
    NSLog(@"[SpotifyEQ10] =====================================");
    NSLog(@"[SpotifyEQ10] Tweak loaded! Dynamic UI Edition");
    NSLog(@"[SpotifyEQ10] =====================================");
    
    // Hook SPTEqualizerModel
    Class modelClass = NSClassFromString(@"SPTEqualizerModel");
    if (modelClass) {
        installHook(modelClass, NSSelectorFromString(@"setValues:"), (IMP)new_setValues, &orig_setValues);
        installHook(modelClass, NSSelectorFromString(@"values"), (IMP)new_values, &orig_values);
        installHook(modelClass, NSSelectorFromString(@"bands"), (IMP)new_bands, &orig_bands);
        installHook(modelClass, NSSelectorFromString(@"initWithLocalSettings:audioDriverController:connectManager:remoteConfigurationProperties:preferences:"), (IMP)new_initWithLocalSettings, &orig_initWithLocalSettings);
    } else {
        NSLog(@"[SpotifyEQ10] SPTEqualizerModel not found!");
    }
    
    // Hook UISlider UI Elements
    Class sliderClass = [UISlider class];
    if (sliderClass) {
        installHook(sliderClass, @selector(layoutSubviews), (IMP)new_sliderLayoutSubviews, &orig_sliderLayoutSubviews);
        installHook(sliderClass, @selector(setValue:animated:), (IMP)new_sliderSetValueAnimated, &orig_sliderSetValueAnimated);
    }
    
    NSLog(@"[SpotifyEQ10] Init complete!");
}
