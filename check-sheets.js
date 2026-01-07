#!/usr/bin/env node
const XLSX = require('xlsx');

// Read the Excel file
const workbook = XLSX.readFile('Roguelikes.xlsx');

console.log('Sheets in workbook:');
workbook.SheetNames.forEach((name, idx) => {
  const sheet = workbook.Sheets[name];
  const data = XLSX.utils.sheet_to_json(sheet);
  console.log(`  ${idx + 1}. "${name}" - ${data.length} rows`);
  if (data.length > 0) {
    console.log(`     Columns: ${Object.keys(data[0]).join(', ')}`);
  }
});
