//
//  SGRegex.m
//  aquachat
//
//  Created by Steve Green on 3/29/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "SGRegex.h"

@implementation SGRegex

+ (SGRegex *) regexWithString:(NSString *) regex nSubExpr:(int) nSubExpr
{
	SGRegex *me = [[self alloc] init];
	
	int flags = REG_EXTENDED | REG_ICASE;

	if (nSubExpr)
	{
		me->n_sub_expr = nSubExpr + 1;	// Add one for the entire string
		me->pmatch = (regmatch_t *) malloc (sizeof (regmatch_t) * me->n_sub_expr);
	}
	else
	{
		me->n_sub_expr = 0;
		flags |= REG_NOSUB;
		me->pmatch = nil;
	}

	memset (&me->preg, 0, sizeof (me->preg));
	int rc = regcomp (&me->preg, [regex UTF8String], flags);
	if (rc != 0)
		printf ("Unable to compile ->%s<- code = %d\n", [regex UTF8String], rc);
	me->ok = (rc == 0);
	
	return [me autorelease];
}

- (void) dealloc
{
	free (pmatch);
	regfree (&preg);
	[list release];
	[super dealloc];
}

- (BOOL) doitWithString:(NSString *) input
{
	return [self doitWithCString:[input UTF8String] encoding:NSUTF8StringEncoding];
}

- (BOOL) doitWithUTF8String:(const char *) input
{
	return [self doitWithCString:input encoding:NSUTF8StringEncoding];
}

- (BOOL) doitWithCString:(const char *) input encoding:(NSStringEncoding) enc
{
	[list release];
	list = [[NSMutableArray alloc] initWithCapacity:n_sub_expr];

	if (ok && regexec (&preg, input, n_sub_expr, pmatch, 0) == 0)
	{
		// Start at 1!!!
		for (size_t i = 1; i < n_sub_expr; i ++)
		{
			regmatch_t *match = &pmatch [i];

			if (match->rm_so != -1)
			{
				regoff_t l = match->rm_eo - match->rm_so;
				[list addObject:[[[NSString alloc] initWithBytes:input + match->rm_so length:l encoding:enc] autorelease]];
			}
			else
				[list addObject:@""];
		} 

		return true;
	}

	return false;
}

- (NSString *) getNthMatch:(NSInteger) n
{
	return [list objectAtIndex:n];
}

@end
