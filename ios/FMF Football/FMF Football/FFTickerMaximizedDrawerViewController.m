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
        self.view.frame = CGRectMake(0, 0, 320, 95);
        
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 320, 15)];
        lab.text = NSLocalizedString(@"Real-Time Market Rates", nil);
        lab.font = [FFStyle lightFont:17];
        lab.textColor = [FFStyle white];
        lab.backgroundColor = [UIColor clearColor];
        
        self.errorLabel.frame = CGRectMake(10, 0, 300, 95);
        self.loadingLabel.frame = CGRectMake(42, 0, 300, 95);
        self.activityIndicator.frame = CGRectMake(18, 43, 10, 10);
        
        [self.view addSubview:lab];
        
        self.collectionView.frame = CGRectMake(0, 30, 320, 65);
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
    NSDictionary *player = [self.tickerData objectAtIndex:indexPath.row];
    
    NSString *nameValue = [NSString stringWithFormat:@"%@ (%@)", player[@"name"], player[@"position"]];
    CGFloat namw = [nameValue sizeWithFont:[FFStyle regularFont:15]
                         constrainedToSize:CGSizeMake(150, 100)].width;
    return CGSizeMake(56+namw, 65);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"MaxCell"
                                                                           forIndexPath:indexPath];
    
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    NSDictionary *player = [self.tickerData objectAtIndex:indexPath.row];
    
    UIImageView *img = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    img.contentMode = UIViewContentModeScaleAspectFit;
    [cell.contentView addSubview:img];
    [img setImageWithURL:[NSURL URLWithString:player[@"headshot_url"]]
        placeholderImage:[UIImage imageNamed:@"helmet-placeholder.png"]];
    
    UIImageView *overlay = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    overlay.contentMode = UIViewContentModeScaleAspectFit;
    overlay.image = [UIImage imageNamed:@"player-cutout.png"];
    overlay.backgroundColor = [UIColor clearColor];
    [cell.contentView addSubview:overlay];
    
    NSString *nameValue = [NSString stringWithFormat:@"%@ (%@)", player[@"name"], player[@"position"]];
    CGFloat namw = [nameValue sizeWithFont:[FFStyle regularFont:15]
                         constrainedToSize:CGSizeMake(150, 100)].width;
    UILabel *nam = [[UILabel alloc] initWithFrame:CGRectMake(56, 5, namw, 15)];
    nam.font = [FFStyle regularFont:15];
    nam.textColor = [FFStyle white];
    nam.backgroundColor = [FFStyle darkGreen];
    nam.text = nameValue;
    [cell.contentView addSubview:nam];
    
    NSString *ppgValue = [NSString stringWithFormat:@"%@ PPG", (![player[@"ppg"] isEqual:[NSNull null]]
                                                                ? player[@"ppg"]
                                                                : @"0")];
    UILabel *ppg = [[UILabel alloc] initWithFrame:CGRectMake(56, 23, 60, 15)];
    ppg.textColor = [FFStyle white];
    ppg.backgroundColor = [FFStyle darkGreen];
    ppg.font = [FFStyle regularFont:12];
    ppg.text = ppgValue;
    [cell.contentView addSubview:ppg];
    
    double currency = [player[@"buy_price"] doubleValue];
    static NSNumberFormatter *formatter = nil;
    if (!formatter) {
        formatter = [[NSNumberFormatter alloc] init];
        [formatter setNumberStyle: NSNumberFormatterCurrencyStyle];
    }
    NSString *costValue = [formatter stringFromNumber:[NSNumber numberWithDouble:currency]];
    UILabel *cost = [[UILabel alloc] initWithFrame:CGRectMake(56, 38, 100, 15)];
    cost.textColor = [FFStyle white];
    cost.backgroundColor = [FFStyle darkGreen];
    cost.font = [FFStyle regularFont:12];
    cost.text = costValue;
    [cell.contentView addSubview:cost];
    
    return cell;
}

@end
