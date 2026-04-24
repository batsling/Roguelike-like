#!/usr/bin/env node
const XLSX = require('xlsx');

// Read the Excel file
const workbook = XLSX.readFile('Roguelikes.xlsx');
const sheet = workbook.Sheets[workbook.SheetNames[0]];

// Convert to JSON
const data = XLSX.utils.sheet_to_json(sheet);

console.log('Total rows:', data.length);
console.log('\nFirst row columns:');
console.log(Object.keys(data[0]));
console.log('\nFirst row data:');
console.log(JSON.stringify(data[0], null, 2));
