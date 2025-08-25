if (typeof expect !== 'undefined' && !expect.addEqualityTesters) {
  // Add the missing method as a no-op or basic implementation
  expect.addEqualityTesters = function(testers) {
    // Store testers for potential future use
    expect._customTesters = expect._customTesters || [];
    expect._customTesters.push(...testers);
    
    console.warn('addEqualityTesters partially implemented - some Jest functionality may not work');
  };
}

jest.setTimeout(30000);