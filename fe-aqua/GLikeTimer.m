/* GLikeTimer
 * Copyright (C) 2005 Camillo Lugaresi
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA */

/*
    GLikeTimer.m
    Created by Camillo Lugaresi on 04/09/05.
    
    An NSTimer wrapper with semantics compatible with those of glib's timers.
    g_timeout_add -> addTaggedTimerWithMSInterval:callback:userData:
    g_source_remove -> removeTimerWithTag:
*/

#import "GLikeTimer.h"

@implementation GLikeTimer

- (id)initWithFunction:(GSourceFunc)func userData:(gpointer)data
{
    if ((self = [super init])) {
        self->function = func;
        self->userData = data;
    }
    return self;
}

+ (NSTimer *)scheduledTimerWithMSInterval:(guint)ms callback:(GSourceFunc)function userData:(gpointer)data
{
    GLikeTimer *gTimer = [[GLikeTimer alloc] initWithFunction:function userData:data];
    [gTimer autorelease];    // NSTimer retains target and userInfo until it is invalidated
    return [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)ms/1000.0
                                            target:gTimer
                                          selector:@selector(doCallback:)
                                          userInfo:nil
                                           repeats:YES];
}

/*
    I do the simplest thing that could possibly work: using the NSTimer * as the tag.
    If necessary, this can be changed to something more sophisticated...
    Ok, now we have something more sophisticated. When compiling a 64-bit version of
    XCA, you'll probably want to set POINTERS_ARE_TAGS to 0.
*/

#define GLIKETIMER_32BIT_ONLY 0
#if GLIKETIMER_32BIT_ONLY

+ (guint)addTaggedTimerWithMSInterval:(guint)ms callback:(GSourceFunc)function userData:(gpointer)data
{
    return (guint)[self scheduledTimerWithMSInterval:ms callback:function userData:data];
}

+ (gboolean)removeTimerWithTag:(guint)tag
{
    //FIXME: 32bit only
    [(NSTimer *)tag invalidate];
    return true;
}

- (void)doCallback:(NSTimer*)timer
{
    if ((function(userData) == 0) && [timer isValid])   // note: glib allows callers to remove the timer
        [timer invalidate];                             // explicitly from within the callback, and then
}                                                       // return 0. Guard against this by using isValid.

#else

NSMutableDictionary *gTimers;

+ (guint)addTaggedTimerWithMSInterval:(guint)ms callback:(GSourceFunc)function userData:(gpointer)data
{
    NSTimer *timer = [self scheduledTimerWithMSInterval:ms callback:function userData:data];
    NSUInteger tag = [timer hash];
    [gTimers setObject:timer forKey:[NSNumber numberWithInteger:tag]];
    return (guint)tag;
}

+ (gboolean)removeTimerWithTag:(guint)tag
{
    id key = [NSNumber numberWithInteger:tag];
    NSTimer *timer = [gTimers objectForKey:key];
    if (timer == nil) return false;
    [gTimers removeObjectForKey:key];
    [timer invalidate];
    return true;
}

- (void)doCallback:(NSTimer*)timer
{
    int tag = [timer hash];                     // note: glib allows callers to remove the timer
    if (function(userData) == 0)                // explicitly from within the callback, and then
        [GLikeTimer removeTimerWithTag:tag];    // return 0. removeTimerWithTag has no problem
}                                               // with double-removes, but we need to save the tag.

#endif

+ (void)initialize
{
#if GLIKETIMER_32BIT_ONLY
#else
    gTimers = [NSMutableDictionary dictionaryWithCapacity:5];
#endif
}

@end
