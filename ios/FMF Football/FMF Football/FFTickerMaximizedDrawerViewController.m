//
//  FFTickerMaximizedDrawerViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFTickerMaximizedDrawerViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <AFNetworking/UIImageView+AFNetworking.h>

@interface FFTickerMaximizedDrawerViewController ()

@end

@implementation FFTickerMaximizedDrawerViewController

- (id)init
{
    self = [super init];
    if (self) {
        self.view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 95)];
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 320, 15)];
        lab.text = NSLocalizedString(@"Real-Time Market Rates", nil);
        lab.font = [FFStyle lightFont:17];
        lab.textColor = [FFStyle white];
        lab.backgroundColor = [UIColor clearColor];
        [self.view addSubview:lab];
        
        self.collectionView.frame = CGRectMake(0, 30, 320, 65);
        [self.view addSubview:self.collectionView];
        [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"MaxCell"];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.shouldUpdateTickerData) {
        [self getTicker:^(id successObj) {
            // pass
        } failure:^(NSError *error) {
            // pass
        }];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return CGSizeMake(174, 65);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"MaxCell" forIndexPath:indexPath];
    
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    NSDictionary *player = [self.tickerData objectAtIndex:indexPath.row];
    NSLog(@"player: %@", player);
    
    UIImageView *img = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    [cell.contentView addSubview:img];
    
    cell.backgroundColor = [UIColor purpleColor];
    cell.backgroundView.backgroundColor = [UIColor purpleColor];
    cell.backgroundView.layer.borderColor = [UIColor blackColor].CGColor;
    cell.backgroundView.layer.borderWidth = 1;
    return cell;
}

@end
