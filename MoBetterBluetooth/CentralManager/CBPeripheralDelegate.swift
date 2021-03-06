//
//  CBPeripheralDelegate.swift
//  Toolbox
//
//  Created by Robert Vaessen on 10/30/16.
//  Copyright © 2016 Robert Vaessen. All rights reserved.
//

import UIKit
import CoreBluetooth

extension CentralManager {
    class PeripheralDelegate : NSObject, CBPeripheralDelegate {
        
        let peripheral: Peripheral

        private let factory : CentralManagerTypesFactory
        private var subscription : PeripheralSubscription
        private let eventHandler : Event.Handler
        
        init(peripheral: Peripheral, subscription : PeripheralSubscription, factory: CentralManagerTypesFactory, eventHandler: @escaping CentralManager.Event.Handler) {
            self.peripheral = peripheral
            self.subscription = subscription
            self.factory = factory
            self.eventHandler = eventHandler
        }

        // Discovery **********************************************

        // TODO: Handle included services
        @objc func peripheral(_ cbPeripheral: CBPeripheral, didDiscoverServices error: Error?) {
            guard error == nil else {
                eventHandler(Event.error(ErrorCode.peripheral("Cannot discover peripheral \(peripheral.name)'s services", peripheral, error)))
                return
            }
            
            guard !peripheral.servicesDiscovered else {
                eventHandler(Event.error(ErrorCode.internalError("Peripheral \(peripheral.name)'s services were rediscovered???")))
                return
            }
            
            if let cbServices = cbPeripheral.services, cbServices.count > 0 {
                for cbService in cbServices {
                    guard let id = subscription.match(cbService) else {
                        eventHandler(Event.error(ErrorCode.internalError("didDiscoverServices reported a service [\(cbService)] that does not match the subscription???")))
                        continue
                    }
                    
                    let service = factory.makeService(for: cbService, id: id, parent: peripheral)
                    peripheral.services.append(service)
                    
                    let characteristicUuids = subscription[cbService]?.getCharacteristicUuids()
                    cbPeripheral.discoverCharacteristics(characteristicUuids, for:cbService)
                }
            }
            else if !subscription.services.isEmpty {
                eventHandler(Event.error(ErrorCode.internalError("The peripheral subscription specifies services but didDiscoverServices reported 0 services???")))
            }
            
            peripheral.servicesDiscovered = true
            
            if peripheral.discoveryCompleted {
                eventHandler(Event.peripheralReady(peripheral))
            }
        }
        
        @objc func peripheral(_ cbPeripheral: CBPeripheral, didDiscoverCharacteristicsFor cbService: CBService, error: Error?) {
            guard let service = peripheral[cbService] else {
                eventHandler(Event.error(ErrorCode.internalError("Characteristics were reported for an unrecognized service: \(cbService)???")))
                return
            }
            
            guard error == nil else {
                eventHandler(Event.error(ErrorCode.service("Cannot discover service \(service.name)'s characteristics", service, error)))
                return
            }
            
            guard !service.characteristicsDiscovered else {
                eventHandler(Event.error(ErrorCode.internalError("Service \(service.name)'s characteristics were rediscovered???")))
                return
            }
            
            if let cbCharacteristics = cbService.characteristics, cbCharacteristics.count > 0 {
                for cbCharacteristic in cbCharacteristics {
                    
                    guard let id = subscription.match(cbCharacteristic, of: cbService) else {
                        eventHandler(Event.error(ErrorCode.internalError("didDiscoverCharacteristicsFor reported a characteristic [\(cbCharacteristic)] that does not match the subscription???")))
                        continue
                    }
                    
                    let characteristic = factory.makeCharacteristic(for: cbCharacteristic, id: id, parent: service)
                    service.characteristics.append(characteristic)
                    
                    var discoverDescriptors = true
                    if let characteristicSubscription = subscription[cbService]?[cbCharacteristic] {
                        discoverDescriptors = characteristicSubscription.discoverDescriptors
                    }
                    if discoverDescriptors {
                        cbPeripheral.discoverDescriptors(for: cbCharacteristic)
                    } else {
                        characteristic.descriptorsDiscovered = true
                    }
                }
            }
            else if let serviceSubscription = subscription[cbService], !serviceSubscription.characteristics.isEmpty {
                eventHandler(CentralManager.Event.error(CentralManager.ErrorCode.internalError("The service subscription specifies characteristics but didDiscoverCharacteristicsFor reported 0 characteristics???")))
            }
            
            service.characteristicsDiscovered = true
            
            if peripheral.discoveryCompleted {
                eventHandler(Event.peripheralReady(peripheral))
            }
        }
        
        @objc func peripheral(_ cbPeripheral: CBPeripheral, didDiscoverDescriptorsFor cbCharacteristic: CBCharacteristic, error: Error?) {
            guard let characteristic = peripheral[cbCharacteristic.service]?[cbCharacteristic] else {
                eventHandler(Event.error(ErrorCode.internalError("Descriptors were reported for an unrecognized characteristic: \(cbCharacteristic)???")))
                return
            }
            
            guard error == nil else {
                eventHandler(Event.error(ErrorCode.characteristic("Cannot discover characteristic \(characteristic.name)'s descriptors", characteristic, error)))
                return
            }
            
            guard !characteristic.descriptorsDiscovered else {
                eventHandler(Event.error(ErrorCode.internalError("Characteristic \(characteristic.name)'s descriptors were rediscovered???")))
                return
            }
            
            if let cbDescriptors = cbCharacteristic.descriptors, cbDescriptors.count > 0 {
                for cbDescriptor in cbDescriptors {
                    let id = CentralManager.Identifier(uuid: cbDescriptor.uuid, name: nil)
                    let descriptor = factory.makeDescriptor(for: cbDescriptor, id: id, parent: characteristic)
                    characteristic.descriptors.append(descriptor)
                }
            }
            
            characteristic.descriptorsDiscovered = true
            
            if peripheral.discoveryCompleted {
                eventHandler(Event.peripheralReady(peripheral))
            }
        }
        
        // Characteristic Read/Write/Notify **********************************************

        @objc func peripheral(_ cbPeripheral: CBPeripheral, didUpdateValueFor cbCharacteristic: CBCharacteristic, error: Error?) {
            guard let characteristic = peripheral[cbCharacteristic.service]?[cbCharacteristic] else {
                eventHandler(Event.error(ErrorCode.internalError("Cannot find the characteristic corresponding to: \(cbCharacteristic)???")))
                return
            }
            
            characteristic.readCompleted(cbCharacteristic.value, cbError: error)
        }
        
        @objc func peripheral(_ cbPeripheral: CBPeripheral, didWriteValueFor cbCharacteristic: CBCharacteristic, error: Error?) {
            guard let characteristic = peripheral[cbCharacteristic.service]?[cbCharacteristic] else {
                eventHandler(Event.error(ErrorCode.internalError("Cannot find the characteristic corresponding to: \(cbCharacteristic)???")))
                return
            }
            
            characteristic.writeCompleted(cbError: error)
        }
        
        @objc func peripheral(_ cbPeripheral: CBPeripheral, didUpdateNotificationStateFor cbCharacteristic: CBCharacteristic, error: Error?) {
            guard let characteristic = peripheral[cbCharacteristic.service]?[cbCharacteristic] else {
                eventHandler(Event.error(ErrorCode.internalError("Cannot find the characteristic corresponding to: \(cbCharacteristic)???")))
                return
            }
            
            characteristic.setNotificationStateCompleted(value: cbCharacteristic.isNotifying, cbError: error)
        }

        // Descriptor Read/Write **********************************************

        @objc func peripheral(_ cbPeripheral: CBPeripheral, didUpdateValueFor cbDescriptor: CBDescriptor, error: Error?) {
            guard let descriptor = peripheral[cbDescriptor.characteristic.service]?[cbDescriptor.characteristic]?[cbDescriptor] else {
                eventHandler(Event.error(ErrorCode.internalError("Cannot find the descriptor corresponding to: \(cbDescriptor)???")))
                return
            }
            
            descriptor.readCompleted(value: cbDescriptor.value, cbError: error)
        }
        
        @objc func peripheral(_ cbPeripheral: CBPeripheral, didWriteValueFor cbDescriptor: CBDescriptor, error: Error?) {
            guard let descriptor = peripheral[cbDescriptor.characteristic.service]?[cbDescriptor.characteristic]?[cbDescriptor] else {
                eventHandler(Event.error(ErrorCode.internalError("Cannot find the descriptor corresponding to: \(cbDescriptor)???")))
                return
            }
            
            descriptor.writeCompleted(value: cbDescriptor.value, cbError: error)
        }
    }
}
