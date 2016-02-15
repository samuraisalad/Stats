//
//  ViewController.m
//  Stats
//
//  Created by 齋藤 仁 on 2016/02/15.
//  Copyright © 2016年 samuraisalad. All rights reserved.
//

#import "ViewController.h"
#include <sys/sysctl.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>

const int MAX_COUNT = 30;

@interface ViewController ()

@end

@implementation ViewController
{
    processor_info_array_t cpuInfo, prevCpuInfo;
    mach_msg_type_number_t numCpuInfo, numPrevCpuInfo;
    unsigned numCPUs;
    NSTimer *updateTimer;
    NSLock *CPUUsageLock;
    
    int count;
    NSMutableArray *totalCpuArray;
    float totalMemoryUsed;
    float totalMemoryFree;
    float totalMemoryTotal;
    
    UIBackgroundTaskIdentifier bgTask;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    totalCpuArray = [NSMutableArray array];
    count = 0;
    
    int mib[2U] = { CTL_HW, HW_NCPU };
    size_t sizeOfNumCPUs = sizeof(numCPUs);
    int status = sysctl(mib, 2U, &numCPUs, &sizeOfNumCPUs, NULL, 0U);
    if(status)
        numCPUs = 1;
    
    CPUUsageLock = [[NSLock alloc] init];
    
    updateTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                   target:self
                                                 selector:@selector(updateInfo:)
                                                 userInfo:nil
                                                  repeats:YES];
    
    bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [self endBackgroundTask];
    }];
}

- (void)endBackgroundTask {
    if (bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)updateInfo:(NSTimer *)timer
{
    @autoreleasepool {
        [self print_free_memory];
        
        [self print_cpu];
        
        count++;
        
        if (count == MAX_COUNT) {
            NSLog(@"[AVE] MEM: used: %f free: %f total: %f", totalMemoryUsed / MAX_COUNT, totalMemoryFree / MAX_COUNT, totalMemoryTotal / MAX_COUNT);
            
            float totalCpu;
            NSMutableString *str = [[NSMutableString alloc] init];
            [str appendString:@"[AVE] CPU: "];
            for (int i = 0; i < totalCpuArray.count; i++) {
                NSNumber *num = totalCpuArray[i];
                float val = [num floatValue];
                totalCpu += val;
                [str appendFormat:@"Core: %d Usage: %f  ", i, val / MAX_COUNT];
            }
            
            [str appendFormat:@"ave: %f", totalCpu / MAX_COUNT / totalCpuArray.count];
            NSLog(@"%@", str);
            
            
            [totalCpuArray removeAllObjects];
            
            totalMemoryUsed = 0.f;
            totalMemoryFree = 0.f;
            totalMemoryTotal = 0.f;
            
            count = 0;
        }
    }
    
}

- (void)print_free_memory
{
    mach_port_t host_port;
    mach_msg_type_number_t host_size;
    vm_size_t pagesize;
    
    host_port = mach_host_self();
    host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    host_page_size(host_port, &pagesize);
    
    vm_statistics_data_t vm_stat;
    
    if (host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size) != KERN_SUCCESS) {
        NSLog(@"Failed to fetch vm statistics");
    }
    
    /* Stats in bytes */
    natural_t mem_used = (vm_stat.active_count +
                          vm_stat.inactive_count +
                          vm_stat.wire_count) * pagesize;
    natural_t mem_free = vm_stat.free_count * pagesize;
    natural_t mem_total = mem_used + mem_free;
    
    float mem_used_g = mem_used/1024.0f/1024.0f;
    float mem_free_g = mem_free/1024.0f/1024.0f;
    float mem_total_g = mem_total/1024.0f/1024.0f;
    NSLog(@"MEM: used: %f free: %f total: %f", mem_used_g, mem_free_g, mem_total_g);
    
    totalMemoryUsed += mem_used_g;
    totalMemoryFree += mem_free_g;
    totalMemoryTotal += mem_total_g;
}

- (void)print_cpu {
    natural_t numCPUsU = 0U;
    kern_return_t err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo);
    if(err == KERN_SUCCESS) {
        [CPUUsageLock lock];
        
        NSMutableString *logString = [[NSMutableString alloc] init];
        [logString appendString:@"CPU: "];
        float totalUsage;
        for(unsigned i = 0U; i < numCPUs; ++i) {
            float inUse, total;
            if(prevCpuInfo) {
                inUse = (
                         (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER])
                         + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM])
                         + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE])
                         );
                total = inUse + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE]);
            } else {
                inUse = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
                total = inUse + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];
            }
            
            float usage = inUse / total * 100.0f;
            totalUsage += usage;
            [logString appendString:[NSString stringWithFormat:@"Core: %u Usage: %f  ",i, usage]];
            
            if (totalCpuArray.count > i) {
                totalCpuArray[i] = [NSNumber numberWithFloat:[totalCpuArray[i] floatValue] + usage];
            } else {
                totalCpuArray[i] = [NSNumber numberWithFloat:usage];
            }
            
            //            NSLog(@"Core: %u Usage: %f",i,inUse / total);
        }
        
        float ave = totalUsage / numCPUs;
        [logString appendString:[NSString stringWithFormat:@"ave: %f", ave]];
        NSLog(@"%@", logString);
        
        [CPUUsageLock unlock];
        
        if(prevCpuInfo) {
            size_t prevCpuInfoSize = sizeof(integer_t) * numPrevCpuInfo;
            vm_deallocate(mach_task_self(), (vm_address_t)prevCpuInfo, prevCpuInfoSize);
        }
        
        prevCpuInfo = cpuInfo;
        numPrevCpuInfo = numCpuInfo;
        
        cpuInfo = NULL;
        numCpuInfo = 0U;
    } else {
        NSLog(@"Error!");
        //        [NSApp terminate:nil];
    }
}

@end
