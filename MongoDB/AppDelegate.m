//
//  AppDelegate.m
//  MongoDB
//
//  Created by diRex,diegofernandes on 3/17/14.
//  Copyright (c) 2014 https://www.mongodb.org/. All rights reserved.
//

#import "AppDelegate.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self setInitParams];
    [self launchMongoDB];
}
-(void) applicationWillTerminate:(NSNotification *)notification{
    [self stop];
}

- (void) awakeFromNib {
    
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSBundle *bundle = [NSBundle mainBundle];
    
    statusImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"mongo_db" ofType:@"png"]];
    
    [statusItem setImage:statusImage];
    [statusItem setMenu:statusMenu];
    [statusItem setHighlightMode:true];
    
}

- (IBAction)openDoc:(id)sender {
    NSURL *url = [NSURL URLWithString:@"http://docs.mongodb.org/manual/"];
    if( ![[NSWorkspace sharedWorkspace] openURL:url] )
        NSLog(@"Failed to open url: %@",[url description]);
}


- (NSMutableString *)getMongoDBPath {
    NSMutableString *launchPath = [[NSMutableString alloc] init];
	[launchPath appendString:[[NSBundle mainBundle] resourcePath]];
	[launchPath appendString:@"/mongodb-core"];
    return launchPath;
}

- (NSString *)toParamKey:(id)key {
    NSString *param = [@"--" stringByAppendingString:key];
    return param;
}

- (void) launchMongoDB {
   
    
	in = [[NSPipe alloc] init];
	out = [[NSPipe alloc] init];
	task = [[NSTask alloc] init];
    
    startTime = time(NULL);
    
    NSMutableString *launchPath;
    launchPath = [self getMongoDBPath];
	[task setCurrentDirectoryPath:launchPath];
  
    [launchPath appendString:@"/bin/mongod"];
	[task setLaunchPath:launchPath];
    
    
    NSMutableArray *args =  [[NSMutableArray alloc]init];
    
    [params enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        
        NSString *param;
        param = [self toParamKey:key];
        [args addObject: param];
        [args addObject: obj];

    }];
    

    [task setArguments:args];
    
	[task setStandardInput:in];
	[task setStandardOutput:out];
    
    
	NSFileHandle *fh = [out fileHandleForReading];
	NSNotificationCenter *nc;
	nc = [NSNotificationCenter defaultCenter];
    
	[nc addObserver:self
           selector:@selector(dataReady:)
               name:NSFileHandleReadCompletionNotification
             object:fh];
	
	[nc addObserver:self
           selector:@selector(taskTerminated:)
               name:NSTaskDidTerminateNotification
             object:task];
    
  	[task launch];
  	[fh readInBackgroundAndNotify];
}



-(void)flushLog {
    fflush(logFile);
}
-(void)taskTerminated:(NSNotification *)note{
    [self cleanup];
    NSLog( [NSString stringWithFormat:@"Terminated with status %d\n",
             [[note object] terminationStatus]]);
    
    time_t now = time(NULL);
    if (now - startTime < MIN_LIFETIME) {
        NSInteger b = NSRunAlertPanel(@"Problem Running MongoDB",
                                      @"MongoDB Server doesn't seem to be operating properly.  "
                                      @"Check Console logs for more details.", @"Retry", @"Quit", nil);
        if (b == NSAlertAlternateReturn) {
            [NSApp terminate:self];
        }
    }
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(launchMongoDB) userInfo:nil repeats:NO];
}
- (void)dataReady:(NSNotification *)n{
    NSData *d;
    d = [[n userInfo] valueForKey:NSFileHandleNotificationDataItem];
    if ([d length]) {
        [self appendData:d];
    }
    if (task)
        [[out fileHandleForReading] readInBackgroundAndNotify];
}


- (void)appendData:(NSData *)d {
    NSString *s = [[NSString alloc] initWithData: d
                                        encoding: NSUTF8StringEncoding];
    
    NSLog(@"Mongod Console: %@",s);
    
}

-(void)cleanup{
    
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)stop{
    [task terminate];
}

-(IBAction)stop:(id)sender{
    [task terminate];
}


- (NSURL *)applicationSupportFolder {
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSFileManager*fm = [NSFileManager defaultManager];
    NSURL*    dirPath = nil;
    
    // Find the application support directory in the home directory.
    NSArray* appSupportDir = [fm URLsForDirectory:NSApplicationSupportDirectory
                                        inDomains:NSUserDomainMask];
    if ([appSupportDir count] > 0)
    {
        // Append the bundle ID to the URL for the
        // Application Support directory
        dirPath = [[appSupportDir objectAtIndex:0] URLByAppendingPathComponent:bundleID];
        
        // If the directory does not exist, this method creates it.
        // This method call works in OS X 10.7 and later only.
        NSError*    theError = nil;
        if (![fm createDirectoryAtURL:dirPath withIntermediateDirectories:YES
                           attributes:nil error:&theError])
        {
            // Handle the error.
            
            return nil;
        }
    }
    
    return dirPath;
    
}


- (void)createDiretory:(NSURL *)dir fileManager:(NSFileManager *)fileManager {
    NSError *err;
    if(![fileManager fileExistsAtPath:[dir path]]){
        [fileManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&err];
    }
    if (err) {
        NSLog(@"error create directory %@", err);
    }
}

- (BOOL)createFile:(NSURL *)file fileManager:(NSFileManager *)fileManager {
    NSString *path = [file path];
    if(![fileManager fileExistsAtPath:path]){
        [fileManager createFileAtPath:path contents:nil attributes:nil];
        return YES;
    }
    return NO;
}

-(void)setInitParams {
    NSFileManager* fileManager = [NSFileManager defaultManager];
	
	NSURL *dataDir = [self applicationSupportFolder];
   
    NSURL *dbDir = [dataDir URLByAppendingPathComponent:@"data/db"];
    [self createDiretory:dbDir fileManager:fileManager];
    
    
    NSURL *confDir = [dataDir URLByAppendingPathComponent:@"etc"];
    
   
    
    [self createDiretory:confDir fileManager:fileManager];
    
    NSURL *confFile = [confDir URLByAppendingPathComponent:@"mongodb.conf"];
    
    if (![fileManager fileExistsAtPath:[confFile path]]){
        params = [[NSMutableDictionary alloc] initWithObjects:@[[dbDir path] ,@"27017" ] forKeys:@[@"dbpath",@"port"]];
        
        [params writeToURL:confFile atomically:YES];
    }else{
        params = [[NSMutableDictionary alloc] initWithContentsOfURL:confFile];
    }
    
    
}

-(IBAction)openConsole:(id)sender{
    NSString *s = [NSString stringWithFormat:
                   @"tell application \"Terminal\" to activate do script \"%@/bin/mongo %@ %@\"", [self getMongoDBPath],[self toParamKey:@"port"],[params objectForKey:@"port"]];
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource: s];
    [as executeAndReturnError:nil];
}

@end
