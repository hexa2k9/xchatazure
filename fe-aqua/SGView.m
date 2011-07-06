/* X-Chat Aqua
 * Copyright (C) 2002 Steve Green
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

#import <objc/runtime.h>
#import "SGView.h"

//////////////////////////////////////////////////////////////////////
    
@interface PendingLayouts : NSObject
{
    NSMutableArray *penders;
}
@end

@implementation PendingLayouts

- (id) init
{
    self = [super init];
    penders = [[NSMutableArray alloc] initWithCapacity:10];
    return self;
}

- (void) dealloc
{
    [penders release];
    [super dealloc];
}

- (void) addPendingLayout:(NSView *) v
{
    if ([penders count] == 0)
    {
#if 1
        [[NSRunLoop currentRunLoop] performSelector:@selector (do_layouts)
            target:self argument:nil order:0
            modes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
#else
        [NSApp addAfterEvent:self sel:@selector (do_layouts)];
#endif
    }
    
    [penders addObject:v];
}

- (void) do_layouts
{
    while ([penders count])
    {
        SGView *v = [penders lastObject];
        [v retain];
        [penders removeLastObject];
        [v layout_maybe];
        [v release];
    }
}

+ (void) addPendingLayout:(SGView *) v
{
    static PendingLayouts *pl;
    if (!pl)
        pl = [[PendingLayouts alloc] init];
    [pl addPendingLayout:v];
}

@end

//////////////////////////////////////////////////////////////////////

@interface NSView (sgview)
@end

@implementation NSView (sgview)

// replace deprecated -poseAsClass:
- (void) setOriginalHidden:(BOOL) flag {
    assert(NO);
}

- (void) setSGHidden:(BOOL) flag
{
    [self setOriginalHidden:flag];
    if ([[[self superview] class] isSubclassOfClass:[SGView class]])
        [(SGView *) [self superview] queue_layout];
}

@end

//////////////////////////////////////////////////////////////////////
#ifdef FE_AQUA_TIGER
@interface NSViewOverride : NSView
@end

@implementation NSViewOverride

- (void) setHidden:(BOOL) flag
{
    [super setHidden:flag];
    if ([[[self superview] class] isSubclassOfClass:[SGView class]])
        [(SGView *) [self superview] queue_layout];
}

@end
#endif
//////////////////////////////////////////////////////////////////////

@implementation SGMetaView
@synthesize view, prefSize;

- (id)initWithView:(NSView *)aView;
{
    if ((self = [super init]) != nil) {
        self.view = aView;
        [self reset_prefSize];
    }
    return self;
}

- (id) initWithCoder:(NSCoder *)decoder
{
    if ((self = [super init]) != nil) {
        self.view = [decoder decodeObjectForKey:@"view"];
        lastSize = [decoder decodeRectForKey:@"lastSize"];
        prefSize = [decoder decodeRectForKey:@"prefSize"];
    }
    return self;
}

- (void) encodeWithCoder:(NSCoder *) encoder
{
    [encoder encodeConditionalObject:view forKey:@"view"];
    [encoder encodeRect:lastSize forKey:@"lastSize"];
    [encoder encodeRect:prefSize forKey:@"prefSize"];
}

- (void) dealloc
{
    [view release];
    [super dealloc];
}

- (void) setFrame:(NSRect) frame
{
    //NSLog (@"%x %f %f %f %f", metaView, frame.origin.x,
    //    frame.origin.y, frame.size.width, frame.size.height);
        
    frame = NSIntegralRect (frame);
    self->lastSize = frame;
    [self->view setFrame:frame];
    [self->view setNeedsDisplay:YES];
}

- (void) reset_prefSize
{
    self->prefSize = [view frame];
}

@end

#pragma mark -

@implementation SGView
@synthesize metaViews;

+ (void) initialize
{
    // swap original -setHidden: to new one
    Method originalMethod = class_getInstanceMethod([NSView class], @selector(setHidden:));
    Method overrideMethod = class_getInstanceMethod([NSView class], @selector(setSGHidden:));
    IMP originalImplementation = method_getImplementation(originalMethod);
    IMP overrideImplementation = method_getImplementation(overrideMethod);
    if ( originalImplementation != overrideImplementation ) {
        method_setImplementation(class_getInstanceMethod([NSView class], @selector(setOriginalHidden:)), originalImplementation);
        method_setImplementation(originalMethod, overrideImplementation);
    }
}

- (void) SGViewPrivateInit
{
    [self setAutoresizesSubviews:YES];
    
    self->first_layout = YES;
    self->pending_layout = NO;
    self->in_my_layout = NO;
    self->in_dtor = NO;
}

- (id) initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect]) != nil) {
        [self SGViewPrivateInit];
        metaViews = [[NSMutableArray alloc] init];
    }
    return self;
}

- (id) initWithCoder:(NSCoder *) decoder
{
    if ((self = [super initWithCoder:decoder]) != nil) {
        [self SGViewPrivateInit];
        self->first_layout = NO;    // This feels right
        metaViews = [[NSMutableArray alloc] initWithCoder:decoder];
        for (id metaView in metaViews)
            [self didAddSubview:[metaView view]];
    }
    return self;
}

- (void) encodeWithCoder:(NSCoder *) encoder
{
    [super encodeWithCoder:encoder];
    [metaViews encodeWithCoder:encoder];
}

- (void) dealloc
{
    in_dtor = YES;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [metaViews release];
    [super dealloc];
}

- (void) do_layout
{
}

- (void) setAutoSizeToFit:(BOOL) sf
{
    auto_size_to_fit = sf;
}

- (void) sizeToFit
{
    needs_size_to_fit = NO;
}

- (void) layoutNow
{    
    pending_layout = NO;
    in_my_layout = YES;
    
    if (needs_size_to_fit)
        [self sizeToFit];
        
    [self do_layout];
    [self setNeedsDisplay:YES];

    in_my_layout = NO;
    first_layout = NO;
}

- (void) layout_maybe
{
    if (pending_layout)
        [self layoutNow];
}

#if 0
static void noDisplay (NSView *v)
{
    [v setNeedsDisplay:NO];
    NSArray *sub = [v subviews];
    for (NSUInteger i = 0; i < [sub count]; i ++)
        noDisplay ([sub objectAtIndex:i]);
}
#endif

- (void) queue_layout
{
#if 1
    [self layoutNow];
#else
    if (!pending_layout)
    {
        [PendingLayouts addPendingLayout:self];
        pending_layout = true;
    }
#endif
}

- (void) drawRect:(NSRect) aRect
{
    // Don't let views draw if they have pending layouts
    //[self layout_maybe];
    //if (pending_layout)
        //return;
        
    [super drawRect:aRect];

#if 0
    [[NSColor redColor] set];
    [[NSGraphicsContext currentContext] setShouldAntialias:NO];
    NSBezierPath *p = [NSBezierPath bezierPathWithRect:[self bounds]];
    [p setLineWidth:5];
    [p stroke];
#endif
}

- (SGMetaView *) findViewFor:(NSView *) the_view
{
    NSUInteger i = [self viewOrder:the_view];
    if (i == NSNotFound)
        return nil;
    return [metaViews objectAtIndex:i];
}

- (void) setOrder:(NSUInteger)order forView:(NSView *) the_view
{
    NSUInteger i = [self viewOrder:the_view];
    if (i == NSNotFound)
        return;
    id metaview = [metaViews objectAtIndex:i];
    [metaview retain];
    [metaViews removeObjectAtIndex:i];
    if (order > [metaViews count])
        [metaViews addObject:metaview];
    else
        [metaViews insertObject:metaview atIndex:order];
    [metaview release];
    [self queue_layout];
}

- (NSUInteger) viewOrder:(NSView *) the_view
{
    for (NSUInteger i = 0; i < [metaViews count]; i ++)
    {
        id metaView = [metaViews objectAtIndex:i];
        if ([metaView view] == the_view)
            return i;
    }
    return NSNotFound;
}

//- (void) resizeSubviewsWithOldSize:(NSSize) oldBoundsSize Broken with rotation!
- (void) i_did_resize
{
    if (in_my_layout)
        return;

    // We are being given new dimensions and/or location.
    // If we're being asked to move, then don't do a layout.
    // TBD: This might make sense.. not sure now.
    //if (! NSEqualSizes (oldBoundsSize, [self frame].size))
        [self layoutNow];
}

- (void) setFrame:(NSRect) frameRect
{
    [super setFrame:frameRect];
    [self i_did_resize];
}

- (void) setFrameSize:(NSSize) newSize
{
    [super setFrameSize:newSize];
    [self i_did_resize];
}

- (BOOL) isFlipped
{
    return NO;
}

- (BOOL) isOpaque
{
    return NO;
}

- (void) subview_did_resize:(NSNotification *)notification
{
    // A child view just changed size.  If we are in layout, then we
    // can assume he's changed because we told him to.
    // Sepcifically, we don't want to change the prefSize unless
    // someone other than us changed him.
    
    // in_my_layout is not enough info.. SGViews that change other
    // SGViews that change themselvs causes in_my_layout to be true
    // when we really _do_ want a resize.  See below..
    
    //if (in_my_layout)
        //return;
        
    NSView *subview = (NSView *) [notification object];
    SGMetaView *metaView = [self findViewFor:subview];
    
    if (in_my_layout && (
        NSEqualRects (metaView->lastSize, [subview frame]) ||
        NSEqualRects (metaView->prefSize, [subview frame])))
    {
        return;
    }

    [metaView reset_prefSize];
    
    if (auto_size_to_fit)
        needs_size_to_fit = YES;
        
    [self queue_layout];
}

- (SGMetaView *) metaViewWithView:(NSView *) view
{
    return [[[SGMetaView alloc] initWithView:view] autorelease];
}

- (void) didAddSubview:(NSView *) subview
{
    [super didAddSubview:subview];

    if ([self findViewFor:subview] == nil)
        [metaViews addObject:[self metaViewWithView:subview]];

        [subview setPostsFrameChangedNotifications:true];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector (subview_did_resize:)
                                                     name:NSViewFrameDidChangeNotification
                                                   object:subview];
    
    if (auto_size_to_fit)
        needs_size_to_fit = YES;

    [self queue_layout];
}

- (void) willRemoveSubview:(NSView *) subview
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSViewFrameDidChangeNotification 
                                                  object:subview];

    [super willRemoveSubview:subview];

    if (in_dtor)
        return;
            
    id metaView = [self findViewFor:subview];
    [metaViews removeObject:metaView];
    
    if (auto_size_to_fit)
        needs_size_to_fit = YES;

    [self queue_layout];
}

- (void) replaceSubview:(NSView *)oldView with:(NSView *)newView
{
    // We are about to remove oldView and add newView.
    // We'll need to stuff our metadata back in
    
    SGMetaView *metaView = [self findViewFor:oldView];

    if (metaView)
        [metaView setView:newView];
    
    [super replaceSubview:oldView with:newView];
}

@end
