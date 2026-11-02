if(name=="golden_good")begin
 expected_count=2;expected_overflow=0;expected_truncated=0;
 expected_status=0;expected_score=6;expected_flip=0;
 expected_mean0=101;expected_mean180=100;expected_cost0=9697;expected_cost180=17509;
 expected_peak_x=21;expected_peak_y=12;
 expected_x0=40;expected_y0=104;expected_x1=1208;expected_y1=624;
end
else if(name=="golden_missing_pad")begin
 expected_count=1;expected_overflow=0;expected_truncated=0;
 expected_status=1;expected_score=243;expected_flip=0;
 expected_mean0=87;expected_mean180=87;expected_cost0=12774;expected_cost180=13972;
 expected_peak_x=10;expected_peak_y=7;
 expected_x0=176;expected_y0=104;expected_x1=1200;expected_y1=576;
end
else if(name=="golden_missing_corner")begin
 expected_count=1;expected_overflow=0;expected_truncated=0;
 expected_status=1;expected_score=296;expected_flip=0;
 expected_mean0=92;expected_mean180=92;expected_cost0=12810;expected_cost180=14755;
 expected_peak_x=8;expected_peak_y=16;
 expected_x0=160;expected_y0=176;expected_x1=1040;expected_y1=568;
end
else fail("unknown fixture name");
