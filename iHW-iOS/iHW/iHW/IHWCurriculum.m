//
//  IHWLogic.m
//  iHW
//
//  Created by Jonathan Burns on 7/10/13.
//  Copyright (c) 2013 Jonathan Burns. All rights reserved.
//

#import "IHWCurriculum.h"
#import "IHWAppDelegate.h"
#import "CJSONSerializer.h"
#import "CJSONDeserializer.h"
#import "IHWFileManager.h"
#import "IHWHoliday.h"
#import "IHWNormalDay.h"
#import "IHWCustomDay.h"
#import "IHWUtils.h"
#import "IHWNote.h"

static IHWCurriculum *currentCurriculum;

#pragma mark ****************PRIVATE INSTANCE VARS*****************

@implementation IHWCurriculum {
    BOOL currentlyCaching;
}

#pragma mark -
#pragma mark *******************STATIC STUFF***********************

+ (IHWCurriculum *)currentCurriculum {
    return [self curriculumWithCampus:[self currentCampus] andYear:[self currentYear]];
}

+ (IHWCurriculum *)reloadCurrentCurriculum {
    currentCurriculum = nil;
    return [IHWCurriculum currentCurriculum];
}

+ (IHWCurriculum *)curriculumWithCampus:(int)campus andYear:(int)year {
    if (currentCurriculum == nil || currentCurriculum.campus != campus || currentCurriculum.year != year) {
        [self setCurrentCampus:campus];
        [self setCurrentYear:year];
        //NSLog(@"Creating current curriculum: %@", [IHWDate today]);
        currentCurriculum = [[IHWCurriculum alloc] initWithCampus:campus year:year startingDate:[IHWDate today]];
    } else {
        if (!currentCurriculum.isLoaded && !currentCurriculum.isLoading) [currentCurriculum loadEverythingWithStartingDate:[IHWDate today]];
    }
    return currentCurriculum;
}

+ (int)currentYear {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"currentYear"];
}

+ (int)currentCampus {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"currentCampus"];
}

+ (void)setCurrentYear:(int)year {
    [[NSUserDefaults standardUserDefaults] setInteger:year forKey:@"currentYear"];
}

+ (void)setCurrentCampus:(int)campus {
    [[NSUserDefaults standardUserDefaults] setInteger:campus forKey:@"currentCampus"];
}

+ (BOOL)isFirstRun {
    if ([IHWCurriculum currentYear] == 0 || [IHWCurriculum currentCampus] == 0) return YES;
    else {
        NSString *campusChar = getCampusChar([IHWCurriculum currentCampus]);
        NSData *yearJSON = [IHWFileManager loadYearJSONForYear:[IHWCurriculum currentYear] campus:campusChar];
        if (yearJSON == nil || [yearJSON isEqualToData:[NSData data]]) return YES;
        NSError *error;
        NSDictionary *yearDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:yearJSON error:&error];
        if (error != nil || yearDict == nil) return YES;
        if ([yearDict objectForKey:@"courses"] == nil || [[yearDict objectForKey:@"courses"] count] == 0) return YES;
    }
    return NO;
}

#pragma mark -
#pragma mark ******************INSTANCE STUFF**********************
#pragma mark -
#pragma mark ******************LOADING STUFF***********************

- (id)initWithCampus:(int)campus year:(int)year startingDate:(IHWDate *)date
{
    self = [super init];
    if (self) {
        self.campus = campus;
        self.year = year;
        self.loadingProgress = -1;
        self.curriculumLoadingListeners = [[NSMutableSet alloc] init];
        IHWDate *earliest = [[IHWDate alloc] initWithMonth:7 day:1 year:year];
        IHWDate *latest = [[[IHWDate alloc] initWithMonth:7 day:1 year:year+1] dateByAddingDays:-1];
        if ([date compare:earliest] == NSOrderedAscending) date = earliest;
        else if ([date compare:latest] == NSOrderedDescending) date = latest;
        [self loadEverythingWithStartingDate:date];
    }
    return self;
}

- (void)loadEverythingWithStartingDate:(IHWDate *)date {
    //NSLog(@">loading everything");
    if (self.loadingProgress >= 0) return;
    self.loadingProgress = 0;
    self.loadingQueue = [[NSOperationQueue alloc] init];
    NSBlockOperation *loadSchedule = [NSBlockOperation blockOperationWithBlock:^{
        if (![self downloadParseScheduleJSON]) [self performSelectorOnMainThread:@selector(loadingFailed) withObject:nil waitUntilDone:NO];
    }];
    NSBlockOperation *loadCourses = [NSBlockOperation blockOperationWithBlock:^{
        if (![self loadCourses]) [self performSelectorOnMainThread:@selector(loadingFailed) withObject:nil waitUntilDone:NO];
    }];
    NSBlockOperation *loadDayNumbers = [NSBlockOperation blockOperationWithBlock:^{
        if (![self loadDayNumbers]) [self performSelectorOnMainThread:@selector(loadingFailed) withObject:nil waitUntilDone:NO];
    }];
    [loadDayNumbers addDependency:loadSchedule];
    NSBlockOperation *loadWeekAndDay = [NSBlockOperation blockOperationWithBlock:^{
        if (![self loadWeekAndDay:date]) [self performSelectorOnMainThread:@selector(loadingFailed) withObject:nil waitUntilDone:NO];
    }];
    [loadWeekAndDay addDependency:loadSchedule];
    [loadWeekAndDay addDependency:loadDayNumbers];
    [loadWeekAndDay addDependency:loadCourses];
    [self.loadingQueue addOperation:loadSchedule];
    [self.loadingQueue addOperation:loadCourses];
    [self.loadingQueue addOperation:loadDayNumbers];
    [self.loadingQueue addOperation:loadWeekAndDay];
    [self.loadingQueue addObserver:self forKeyPath:@"operationCount" options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)loadingFailed {
    [self.loadingQueue setSuspended:YES];
    self.loadingProgress = -1;
    __block NSMutableSet *toSendSelector = [NSMutableSet set];
    for (NSObject<IHWCurriculumLoadingListener> *mll in self.curriculumLoadingListeners) {
        if ([mll respondsToSelector:@selector(curriculumFailedToLoad:)])
            [toSendSelector addObject:mll];
    }
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [toSendSelector makeObjectsPerformSelector:@selector(curriculumFailedToLoad:) withObject:self];
    }];
}

- (BOOL)isLoading {
    return (self.loadingProgress == 0);
}

- (BOOL)isLoaded {
    return (self.loadingProgress == 1);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"operationCount"] && object == self.loadingQueue) {
        //NSLog(@"loading queue changed count: %d", self.loadingQueue.operationCount);
        if (self.loadingQueue.operationCount == 0) {
            [self.loadingQueue removeObserver:self forKeyPath:@"operationCount"];
            self.loadingQueue = nil;
            self.loadingProgress = 1;
            __block NSMutableArray *toSendSelector = [NSMutableArray array];
            for (NSObject<IHWCurriculumLoadingListener> *mll in self.curriculumLoadingListeners) {
                if ([mll respondsToSelector:@selector(curriculumFinishedLoading:)]) {
                    [toSendSelector addObject:mll];
                }
            }
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [toSendSelector makeObjectsPerformSelector:@selector(curriculumFinishedLoading:) withObject:self];
            }];
        }
    }
}

- (BOOL)dayIsLoaded:(IHWDate *)date {
    if (self.loadedDays == nil || self.loadedWeeks == nil) return NO;
    if ([NSThread isMainThread]) {
    return ([self.loadedDays objectForKey:date] != nil
            && [self.loadedWeeks objectForKey:getWeekStart(self.year, date)] != nil);
    } else {
        __block BOOL result;
        NSOperation *oper = [NSBlockOperation blockOperationWithBlock:^{
            result = ([self.loadedDays objectForKey:date] != nil
                      && [self.loadedWeeks objectForKey:getWeekStart(self.year, date)] != nil);
        }];
        [[NSOperationQueue mainQueue] addOperation:oper];
        [oper waitUntilFinished];
        return result;
    }
}

- (BOOL)downloadParseScheduleJSON {
    //NSLog(@">downloading schedule JSON");
    NSError *error = nil;
    NSURLResponse *response = nil;
    NSString *urlStr = [NSString stringWithFormat:@"http://www.burnsfamily.info/curriculum%d%@.hws", self.year, getCampusChar(self.campus)];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:urlStr] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:5];
    [(IHWAppDelegate *)[UIApplication sharedApplication].delegate performSelectorOnMainThread:@selector(showNetworkIcon) withObject:nil waitUntilDone:NO];
    NSData *scheduleJSON = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    [(IHWAppDelegate *)[UIApplication sharedApplication].delegate performSelectorOnMainThread:@selector(hideNetworkIcon) withObject:nil waitUntilDone:NO];
    //NSData *scheduleJSON = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlStr] options:0 error:&error];
    NSString *campusChar = getCampusChar(self.campus);
    if (error != nil) {
        NSLog(@"ERROR downloading schedule JSON: %@", error.debugDescription);
        scheduleJSON = [IHWFileManager loadScheduleJSONForYear:self.year campus:campusChar];
    } else {
        [IHWFileManager saveScheduleJSON:scheduleJSON forYear:self.year campus:campusChar];
    }
    if (scheduleJSON == nil) return NO;
    else [self parseScheduleJSON:scheduleJSON];
    return YES;
}

- (BOOL)parseScheduleJSON:(NSData *)scheduleJSON {
    //NSLog(@">parsing schedule JSON");
    NSError *error = nil;
    NSDictionary *scheduleDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:scheduleJSON error:&error];
    if (error != nil) { NSLog(@"ERROR parsing schedule JSON: %@", error.debugDescription); return NO; }
    NSMutableArray *semesterEndDates = [NSMutableArray array];
    for (NSString *str in [scheduleDict objectForKey:@"semesterEndDates"]) {
        [semesterEndDates addObject:[[IHWDate alloc] initFromString:str]];
    }
    self.semesterEndDates = semesterEndDates;
    NSMutableArray *trimesterEndDates = [NSMutableArray array];
    for (NSString *str in [scheduleDict objectForKey:@"trimesterEndDates"]) {
        [trimesterEndDates addObject:[[IHWDate alloc] initFromString:str]];
    }
    self.trimesterEndDates = trimesterEndDates;
    if ([scheduleDict objectForKey:@"dayStartTime"] != nil)
        self.dayStartTime = [[IHWTime alloc] initFromString:[scheduleDict objectForKey:@"dayStartTime"]];
    else self.dayStartTime = [[IHWTime alloc] initWithHour:8 andMinute:0];
    self.normalDayTemplate = [scheduleDict objectForKey:@"normalDay"];
    self.normalMondayTemplate = [scheduleDict objectForKey:@"normalMonday"];
    self.passingPeriodLength = [[scheduleDict objectForKey:@"passingPeriodLength"] intValue];
    
    NSMutableDictionary *specialDays = [[NSMutableDictionary alloc] init];
    NSDictionary *specialDaysJSON = [scheduleDict objectForKey:@"specialDays"];
    for (NSString *dateStr in [specialDaysJSON allKeys]) {
        [specialDays setObject:[specialDaysJSON objectForKey:dateStr] forKey:[[IHWDate alloc] initFromString:dateStr]];
    }
    self.specialDayTemplates = [NSDictionary dictionaryWithDictionary:specialDays];
    return YES;
}

- (BOOL)loadCourses {
    //NSLog(@">loading courses");
    NSMutableArray *courseArray = [NSMutableArray array];
    NSError *error = nil;
    NSData *json = [IHWFileManager loadYearJSONForYear:self.year campus:getCampusChar(self.campus)];
    if (json == nil || [json isEqualToData:[NSData data]]) json = generateBlankYearJSON(self.campus, self.year);
    NSDictionary *fromJSON = [[CJSONDeserializer deserializer] deserializeAsDictionary:json error:&error];
    NSArray *coursesJSON = [fromJSON objectForKey:@"courses"];
    if (error != nil) { NSLog(@"ERROR loading courses: %@", error.debugDescription); return NO; }
    for (NSDictionary *dict in coursesJSON) {
        IHWCourse *course = [[IHWCourse alloc] initWithJSONDictionary:dict];
        [courseArray addObject:course];
    }
    self.courses = courseArray;
    return YES;
}

- (BOOL)loadDayNumbers {
    //NSLog(@">loading day numbers");
    if (self.specialDayTemplates == nil || self.semesterEndDates == nil) return NO;
    NSMutableDictionary *dayNums = [[NSMutableDictionary alloc] init];
    IHWDate *d = [self.semesterEndDates objectAtIndex:0];
    int dayNum = 1;
    while ([d compare:[self.semesterEndDates objectAtIndex:2]] != NSOrderedDescending) {
        if ([self.specialDayTemplates objectForKey:d] != nil) {
            if ([[[self.specialDayTemplates objectForKey:d] objectForKey:@"type"] isEqualToString:@"normal"]) {
                int thisNum = [[[self.specialDayTemplates objectForKey:d] objectForKey:@"dayNumber"] intValue];
                if (thisNum != 0) dayNum = thisNum+1;
                [dayNums setObject:[NSNumber numberWithInt:thisNum] forKey:d];
            } else {
                [dayNums setObject:[NSNumber numberWithInt:0] forKey:d];
            }
        } else if (![d isWeekend]) {
            [dayNums setObject:[NSNumber numberWithInt:dayNum] forKey:d];
            dayNum++;
        }
        if (dayNum > self.campus) dayNum -= self.campus;
        d = [d dateByAddingDays:1];
    }
    self.dayNumbers = dayNums;
    return YES;
}

- (BOOL)loadWeekAndDay:(IHWDate *)date {
    if ([date compare:[[IHWDate alloc] initWithMonth:7 day:1 year:self.year]] == NSOrderedAscending) {
        date = [[IHWDate alloc] initWithMonth:7 day:1 year:self.year];
    }
    else if ([date compare:[[IHWDate alloc] initWithMonth:7 day:1 year:self.year+1]] != NSOrderedAscending) {
        date = [[[IHWDate alloc] initWithMonth:7 day:1 year:self.year+1] dateByAddingDays:-1];
    }
    BOOL success = [self loadWeek:date];
    if (!success) { NSLog(@"ERROR loading week: %@", date.description); return NO; }
    success = [self loadDay:date];
    if (!success) { NSLog(@"ERROR loading day: %@", date.description); return NO; }
    return YES;
}

- (BOOL)loadWeek:(IHWDate *)date {
    int weekNumber = getWeekNumber(self.year, date);
    IHWDate *weekStart = getWeekStart(self.year, date);
    //NSLog(@">loading week: %@", weekStart.description);
    if (self.loadedWeeks != nil && [self.loadedWeeks objectForKey:weekStart] != nil) return YES;
    if (weekNumber == -1) return NO;
    NSData *weekJSON = [IHWFileManager loadWeekJSONForWeekNumber:weekNumber year:self.year campus:getCampusChar(self.campus)];
    if (weekJSON == nil) weekJSON = generateBlankWeekJSON(weekStart);
    NSError *error = nil;
    NSDictionary *weekDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:weekJSON error:&error];
    if (error == nil) {
        if (self.loadedWeeks == nil) self.loadedWeeks = [NSMutableDictionary dictionary];
        //[self.loadedWeeks insertObject:weekDict forKey:weekStart sortedUsingComparator:[IHWDate comparator]];
        [self.loadedWeeks setObject:weekDict forKey:weekStart];
    }
    else NSLog(@"ERROR loading week: %@", error.debugDescription);
    return error == nil;
}

- (BOOL)loadDay:(IHWDate *)date {
    //NSLog(@">loading day: %@", date);
    if (![self dateInBounds:date]) return NO;
    if (self.loadedDays == nil) self.loadedDays = [NSMutableDictionary dictionary];
    NSDictionary *template = [self.specialDayTemplates objectForKey:date];
    if (template == nil) {
        if ([date compare:[self.semesterEndDates objectAtIndex:0]] == NSOrderedAscending
            || [date compare:[self.semesterEndDates objectAtIndex:2]] == NSOrderedDescending) {
            //Date is during Summer
            //[self.loadedDays insertObject:[[IHWHoliday alloc] initWithName:@"Summer" onDate:date] forKey:date sortedUsingComparator:[IHWDate comparator]];
            IHWHoliday *holiday = [[IHWHoliday alloc] initWithName:@"Summer" onDate:date];
            [self performSelectorOnMainThread:@selector(addLoadedDay:) withObject:holiday waitUntilDone:YES];
            return YES;
        } else if (date.isWeekend) {
            //[self.loadedDays insertObject:[[IHWHoliday alloc] initWithName:@"" onDate:date] forKey:date sortedUsingComparator:[IHWDate comparator]];
            IHWHoliday *holiday = [[IHWHoliday alloc] initWithName:@"" onDate:date];
            [self performSelectorOnMainThread:@selector(addLoadedDay:) withObject:holiday waitUntilDone:YES];
            return YES;
        }
    }
    if (template==nil && date.isMonday) {
        NSMutableDictionary *dict = [self.normalMondayTemplate mutableCopy];
        [dict setObject:date.description forKey:@"date"];
        [dict setObject:[self.dayNumbers objectForKey:date] forKey:@"dayNumber"];
        template = dict;
    } else if (template==nil) {
        NSMutableDictionary *dict = [self.normalDayTemplate mutableCopy];
        [dict setObject:date.description forKey:@"date"];
        [dict setObject:[self.dayNumbers objectForKey:date] forKey:@"dayNumber"];
        template = dict;
    }
    NSString *type = [template objectForKey:@"type"];
    //NSLog(@"Type: %@", type);
    IHWDay *day;
    if ([type isEqualToString:@"normal"]) {
        day = [[IHWNormalDay alloc] initWithJSONDictionary:template];
        [(IHWNormalDay *)day fillPeriodsFromCurriculum:self];
    } else if ([type isEqualToString:@"test"]) {
        day = [[IHWCustomDay alloc] initWithJSONDictionary:template];
    } else if ([type isEqualToString:@"holiday"]) {
        day = [[IHWHoliday alloc] initWithJSONDictionary:template];
    } else return NO;
    //[self.loadedDays insertObject:day forKey:date sortedUsingComparator:[IHWDate comparator]];
    [self performSelectorOnMainThread:@selector(addLoadedDay:) withObject:day waitUntilDone:YES];
    return YES;
}

- (void)addLoadedDay:(IHWDay *)day {
    [self.loadedDays setObject:day forKey:day.date];
}

- (IHWDay *)dayWithDate:(IHWDate *)date {
    //NSLog(@"Getting day with date %@", date.description);
    if (![self dateInBounds:date]) return nil;
    if (![self dayIsLoaded:date]) {
        BOOL success = [self loadWeekAndDay:date];
        if (!success) return nil;
    }
    if (![self dayIsLoaded:date]) return nil;
    return [self.loadedDays objectForKey:date];
}

- (void)clearUnneededItems:(IHWDate *)date {
    IHWDate *weekStart = getWeekStart(self.year, date);
    NSMutableArray *weeksNeeded = [NSMutableArray array];
    [weeksNeeded addObject:getWeekStart(self.year, [weekStart dateByAddingDays:-1])];
    [weeksNeeded addObject:weekStart];
    [weeksNeeded addObject:getWeekStart(self.year, [weekStart dateByAddingDays:7])];
    if (self.loadedWeeks != nil)
        self.loadedWeeks = [[self.loadedWeeks dictionaryWithValuesForKeys:weeksNeeded] mutableCopy];
    NSMutableArray *daysNeeded = [NSMutableArray array];
    for (int i=-3; i<=3; i++) [daysNeeded addObject:[date dateByAddingDays:i]];
    if (self.loadedDays != nil)
        self.loadedDays = [[self.loadedDays dictionaryWithValuesForKeys:daysNeeded] mutableCopy];
}

- (BOOL)dateInBounds:(IHWDate *)date {
    return (date != nil
            && [date compare:[[IHWDate alloc] initWithMonth:7 day:1 year:self.year]] != NSOrderedAscending
            && [date compare:[[IHWDate alloc] initWithMonth:7 day:1 year:self.year+1]] == NSOrderedAscending);
}

#pragma mark -
#pragma mark *******************COURSES STUFF**********************

- (NSArray *)allCourseNames {
    NSMutableArray *array = [NSMutableArray array];
    for (IHWCourse *c in self.courses) {
        [array addObject:c.name];
    }
    return [NSArray arrayWithArray:array];
}

- (BOOL)addCourse:(IHWCourse *)c {
    for (IHWCourse *check in self.courses) {
        if (!termsCompatible(check.term, c.term)) {
            if (check.period == c.period) {
                for (int i=1; i<=self.campus; i++) {
                    if ([c meetingOn:i] != MEETING_X_DAY && [check meetingOn:i] != MEETING_X_DAY) return NO;
                }
            } else {
                IHWCourse *later;
                IHWCourse *earlier;
                if (c.period > check.period) {
                    later = c;
                    earlier = check;
                } else {
                    later = check;
                    earlier = c;
                }
                if (ABS(c.period-check.period) == 1) {
                    for (int i=1; i<=self.campus; i++) {
                        if ([earlier meetingOn:i] == MEETING_DOUBLE_AFTER && [later meetingOn:i] != MEETING_X_DAY) return NO;
                        if ([later meetingOn:i] == MEETING_DOUBLE_BEFORE && [earlier meetingOn:i] != MEETING_X_DAY) return NO;
                    }
                } else if (ABS(c.period-check.period) == 2) {
                    for (int i=1; i<=self.campus; i++) {
                        if ([earlier meetingOn:i] == MEETING_DOUBLE_AFTER && [later meetingOn:i] == MEETING_DOUBLE_BEFORE) return NO;
                    }
                }
            }
        }
    }
    [self.courses addObject:c];
    [self.loadedDays removeAllObjects];
    return YES;
}

- (void)removeCourse:(IHWCourse *)c {
    [self.courses removeObject:c];
    [self.loadedDays removeAllObjects];
}

- (void)removeAllCourses {
    [self.courses removeAllObjects];
    [self.loadedDays removeAllObjects];
}

/*
- (BOOL)replaceCourseWithName:(NSString *)oldName withCourse:(IHWCourse *)c {
    IHWCourse *oldCourse = [self courseWithName:oldName];
    [self removeCourse:oldCourse];
    if ([self addCourse:c]) return YES;
    else {
        [self addCourse:oldCourse];
        return NO;
    }
}

- (IHWCourse *)courseWithName:(NSString *)name {
    for (IHWCourse *c in self.courses) if ([c.name isEqualToString:name]) return c;
    return nil;
}*/

- (BOOL)replaceCourseAtIndex:(NSInteger)index withCourse:(IHWCourse *)c {
    IHWCourse *oldCourse = [self courseAtIndex:index];
    [self removeCourse:oldCourse];
    if ([self addCourse:c]) return YES;
    else {
        [self addCourse:oldCourse];
        return NO;
    }
}

- (IHWCourse *)courseAtIndex:(NSInteger)index {
    return [self.courses objectAtIndex:index];
}

- (IHWCourse *)courseMeetingOnDate:(IHWDate *)d period:(int)period {
    if ([d compare:[self.semesterEndDates objectAtIndex:0]] == NSOrderedAscending
        || [d compare:[self.semesterEndDates objectAtIndex:2]] == NSOrderedDescending) return nil;
    int dayNum = [[self.dayNumbers objectForKey:d] intValue];
    NSArray *terms = [self termsFromDate:d];
    if (dayNum == 0) {
        IHWCourse *maxMeetings = nil;
        int max = 1;
        for (IHWCourse *c in self.courses) {
            BOOL termFound = NO;
            for (NSNumber *term in terms) if ([term intValue] == c.term) {
                termFound = YES;
                break;
            }
            if (!termFound) continue;
            if (c.period == period && c.totalMeetings > max) {
                maxMeetings = c;
                max = c.totalMeetings;
            }
        }
        return maxMeetings;
    }
    for (IHWCourse *c in self.courses) {
        BOOL termFound = NO;
        for (NSNumber *term in terms) if ([term intValue] == c.term) {
            termFound = YES;
            break;
        }
        if (!termFound) continue;
        if (c.period == period) {
            if ([c meetingOn:dayNum] != MEETING_X_DAY) return c;
        } else if (period == c.period-1) {
            if ([c meetingOn:dayNum] == MEETING_DOUBLE_BEFORE) return c;
        } else if (period == c.period+1) {
            if ([c meetingOn:dayNum] == MEETING_DOUBLE_AFTER) return c;
        }
    }
    return nil;
}

- (NSArray *)courseListForDate:(IHWDate *)d {
    if ([d compare:[self.semesterEndDates objectAtIndex:0]] == NSOrderedAscending
        || [d compare:[self.semesterEndDates objectAtIndex:2]] == NSOrderedDescending) return nil;
    int dayNum = [[self.dayNumbers objectForKey:d] intValue];
    NSArray *terms = [self termsFromDate:d];
    NSMutableArray *courseList = [NSMutableArray arrayWithCapacity:self.campus+4];
    NSMutableArray *maxMeetings = [NSMutableArray arrayWithCapacity:self.campus+4];
    for (int i=0; i<self.campus+4; i++) {
        [courseList setObject:[NSNull null] atIndexedSubscript:i];
        [maxMeetings setObject:[NSNumber numberWithInt:0] atIndexedSubscript:i];
    }
    for (IHWCourse *c in self.courses) {
        if (![terms containsObject:[NSNumber numberWithInt:c.term]]) continue;
        if (dayNum == 0) {
            int meetings = c.totalMeetings;
            if (meetings > [[maxMeetings objectAtIndex:c.period] intValue]) {
                [courseList setObject:c atIndexedSubscript:c.period];
                [maxMeetings setObject:[NSNumber numberWithInt:meetings] atIndexedSubscript:c.period];
            }
        } else if ([c meetingOn:dayNum] != MEETING_X_DAY) {
            [courseList setObject:c atIndexedSubscript:c.period];
            if ([c meetingOn:dayNum] == MEETING_DOUBLE_BEFORE)
                [courseList setObject:c atIndexedSubscript:c.period-1];
            else if ([c meetingOn:dayNum] == MEETING_DOUBLE_AFTER)
                [courseList setObject:c atIndexedSubscript:c.period+1];
        }
    }
    return [NSArray arrayWithArray:courseList];
}

- (NSArray *)termsFromDate:(IHWDate *)d {
    NSMutableArray *array = [NSMutableArray array];
    if ([d compare:[self.semesterEndDates objectAtIndex:0]] != NSOrderedAscending) {
        if ([d compare:[self.semesterEndDates objectAtIndex:1]] != NSOrderedDescending) {
            [array addObject:[NSNumber numberWithInt:TERM_FULL_YEAR]];
            [array addObject:[NSNumber numberWithInt:TERM_FIRST_SEMESTER]];
        } else if ([d compare:[self.semesterEndDates objectAtIndex:2]] != NSOrderedDescending) {
            [array addObject:[NSNumber numberWithInt:TERM_FULL_YEAR]];
            [array addObject:[NSNumber numberWithInt:TERM_SECOND_SEMESTER]];
        }
    }
    if ([d compare:[self.trimesterEndDates objectAtIndex:0]] != NSOrderedAscending) {
        if ([d compare:[self.trimesterEndDates objectAtIndex:1]] != NSOrderedDescending)
            [array addObject:[NSNumber numberWithInt:TERM_FIRST_TRIMESTER]];
        else if ([d compare:[self.trimesterEndDates objectAtIndex:2]] != NSOrderedDescending)
            [array addObject:[NSNumber numberWithInt:TERM_SECOND_TRIMESTER]];
        else if ([d compare:[self.trimesterEndDates objectAtIndex:1]] != NSOrderedDescending)
            [array addObject:[NSNumber numberWithInt:TERM_THIRD_TRIMESTER]];
    }
    return [NSArray arrayWithArray:array];
}

#pragma mark -
#pragma mark *********************NOTES STUFF*********************

- (NSArray *)notesOnDate:(IHWDate *)date period:(int)period {
    IHWDate *weekStart = getWeekStart(self.year, date);
    BOOL success = true;
    if ([self.loadedWeeks objectForKey:weekStart] == nil) success = [self loadWeek:date];
    if (!success) { NSLog(@"ERROR loading week"); return nil; }
    else {
        NSString *key = [NSString stringWithFormat:@"%@.%d", date.description, period];
        NSDictionary *weekJSON = [self.loadedWeeks objectForKey:weekStart];
        NSArray *notesArr = [[weekJSON objectForKey:@"notes"] objectForKey:key];
        if (notesArr != nil) {
            NSMutableArray *notes = [NSMutableArray array];
            for (int i=0; i<notesArr.count; i++) {
                [notes addObject:[[IHWNote alloc] initWithJSONDictionary:[notesArr objectAtIndex:i]]];
            }
            return [NSArray arrayWithArray:notes];
        } else {
            return [NSArray array];
        }
    }
}

- (void)setNotes:(NSArray *)notes onDate:(IHWDate *)date period:(int)period {
    IHWDate *weekStart = getWeekStart(self.year, date);
    if (![self dayIsLoaded:date]) {
        BOOL success = true;
        if ([self.loadedWeeks objectForKey:weekStart] == nil) success = [self loadWeek:date];
        if (!success) NSLog(@"ERROR loading week");
        if ([self.loadedDays objectForKey:date] == nil) success = [self loadDay:date];
        if (!success) NSLog(@"ERROR loading day");
    }
    if ([self dayIsLoaded:date]) {
        NSString *key = [NSString stringWithFormat:@"%@.%d", date.description, period];
        NSMutableDictionary *weekJSON = [[self.loadedWeeks objectForKey:weekStart] mutableCopy];
        NSMutableDictionary *notesDict = [[weekJSON objectForKey:@"notes"] mutableCopy];
        NSMutableArray *notesArr = [NSMutableArray array];
        for (IHWNote *note in notes) {
            [notesArr addObject:[note saveNote]];
        }
        [notesDict setObject:notesArr forKey:key];
        [weekJSON setObject:notesDict forKey:@"notes"];
        [self.loadedWeeks setObject:weekJSON forKey:weekStart];
    }
}

#pragma mark -
#pragma mark ********************SAVING STUFF*********************

- (void)saveWeekWithDate:(IHWDate *)date {
    //NSLog(@"Saving week");
    IHWDate *weekStart = getWeekStart(self.year, date);
    NSDictionary *weekObj = [self.loadedWeeks objectForKey:weekStart];
    int weekNumber = getWeekNumber(self.year, weekStart);
    NSError *error = nil;
    NSData *data = [[CJSONSerializer serializer] serializeDictionary:weekObj error:&error];
    if (error != nil) { NSLog(@"ERROR saving week JSON"); return; }
    [IHWFileManager saveWeekJSON:data forWeekNumber:weekNumber year:self.year campus:getCampusChar(self.campus)];
}

- (void)saveCourses {
    NSString *campusChar = getCampusChar(self.campus);
    NSMutableDictionary *yearDict = [NSMutableDictionary dictionary];
    [yearDict setObject:[NSNumber numberWithInt:self.year] forKey:@"year"];
    [yearDict setObject:[NSNumber numberWithInt:self.campus] forKey:@"campus"];
    NSMutableArray *courseDicts = [NSMutableArray array];
    for (IHWCourse *c in self.courses) [courseDicts addObject:[c saveCourse]];
    [yearDict setObject:courseDicts forKey:@"courses"];
    NSError *error = nil;
    NSData *yearJSON = [[CJSONSerializer serializer] serializeDictionary:yearDict error:&error];
    if (error != nil) { NSLog(@"ERROR serializing courses: %@", error.debugDescription); return; }
    [IHWFileManager saveYearJSON:yearJSON forYear:self.year campus:campusChar];
}

@end